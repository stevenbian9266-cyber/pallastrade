module PallasTradeStripe
  class Gateway < ::PallasTrade::Gateway
    include PallasTradeStripe::Gateway::PaymentIntents
    include PallasTradeStripe::Gateway::PaymentSessions
    include PallasTradeStripe::Gateway::PaymentSetupSessions
    include PallasTradeStripe::Gateway::Tax if defined?(PallasTradeStripe::Gateway::Tax)

    preference :publishable_key, :password
    preference :secret_key, :password

    WEBHOOK_EVENT_ACTIONS = {
      'payment_intent.succeeded' => :captured,
      'payment_intent.amount_capturable_updated' => :authorized,
      'payment_intent.payment_failed' => :failed,
      # PALLAS-CUSTOM (2026-08-29, PRD-20260829-payments): Checkout Session
      # events (migrated from PaymentIntents).
      'checkout.session.completed' => :captured,
      'checkout.session.async_payment_succeeded' => :captured,
      'checkout.session.async_payment_failed' => :failed,
      'checkout.session.expired' => :canceled,
      # PALLAS-CUSTOM (2026-09-11, PRD-20260911-payments-dsp-p7-1): provider 发起的
      # 资金逆转（chargeback / dispute）事件族。与支付事件不同，它们**不携带
      # payment_session**，因此 parse 层单独分流（见 parse_webhook_event）。
      'charge.dispute.created' => :dispute_created,
      'charge.dispute.updated' => :dispute_updated,
      'charge.dispute.closed' => :dispute_closed,
      'charge.dispute.funds_withdrawn' => :dispute_funds_withdrawn,
      'charge.dispute.funds_reinstated' => :dispute_funds_reinstated
    }.freeze

    # dispute 事件族动作（parse 分流依据；与 PallasTrade::PaymentWebhookEvent::DISPUTE_ACTIONS 对齐）
    DISPUTE_ACTIONS = %i[
      dispute_created dispute_updated dispute_closed
      dispute_funds_withdrawn dispute_funds_reinstated
    ].freeze

    has_one_attached :apple_developer_merchantid_domain_association, service: PallasTrade.private_storage_service_name

    # webhook_keys 反向关联（通过 payment_methods_webhook_keys 中间表）——
    # `create_webhook_endpoint_async` 依赖它判断是否已创建 webhook endpoint。
    # 注意：Gateway 是 PaymentMethod 的 STI 子类，中间表外键是 payment_method_id
    #（不是默认推断的 gateway_id）。
    has_many :payment_methods_webhook_keys, class_name: 'PallasTradeStripe::PaymentMethodsWebhookKey', foreign_key: :payment_method_id, dependent: :destroy
    has_many :webhook_keys, through: :payment_methods_webhook_keys, class_name: 'PallasTradeStripe::WebhookKey'

    validates :preferred_secret_key, :preferred_publishable_key, presence: true
    validate :validate_secret_key, unless: -> { Rails.env.test? }, if: -> { preferred_secret_key.present? }

    after_commit :create_webhook_endpoint_async, on: %i[create update]
    after_commit :register_domain, on: :create

    def webhook_url
      store = stores.first
      return nil unless store

      if PallasTradeStripe::Config[:use_legacy_webhook_handlers]
        StripeEvent::Engine.routes.url_helpers.root_url(host: store.url, protocol: 'https')
      else
        "#{store.formatted_url}/api/v3/webhooks/payments/#{prefixed_id}"
      end
    end

    # PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915-admin 切片3）—— 能力目录（业务方案 §63.3）：
    # Stripe 可配置的前台入口 = 卡支付 + 两个钱包（express）。商家在后台逐项启停 / 命名 / 排序；
    # 未选项化（metadata["optionized"] 缺失）时前台仍按单一默认入口渲染 —— 零感迁移。
    # PALLAS-CUSTOM: PAY-CORE-P0B（PRD-20260920-checkout 切片 P0-B）—— 厂商静态能力声明。
    # ★ 已随收敛切片 2+3（2026-09-21）**下线**：`self.provider_capability` 及其消费层
    #   （`Payments::Providers::*` / 后台诊断卡 / 账户表单）整体删除，Stripe 只保留
    #   `payment_option_catalog`（前台入口清单）这一条稳定事实来源。
    def payment_option_catalog
      [
        # D15 切片3（PRD-20260917-checkout-d15-切片3）：`three_d_secure` = 该入口能否被**强制**认证。
        # 卡入口可（`payment_method_options.card.request_three_d_secure='any'`）；
        # 钱包（Apple Pay / Google Pay）是 token 化快捷流程，**不声明**能力 → 高风险单下不可用（不猜）。
        { 'kind' => 'card', 'frontend_kind' => 'inline', 'display_name' => 'Card', 'three_d_secure' => 'supported' },
        { 'kind' => 'apple_pay', 'frontend_kind' => 'express', 'display_name' => 'Apple Pay', 'three_d_secure' => 'unsupported' },
        { 'kind' => 'google_pay', 'frontend_kind' => 'express', 'display_name' => 'Google Pay', 'three_d_secure' => 'unsupported' }
      ]
    end

    def parse_webhook_event(raw_body, headers)
      event = verify_webhook_signature(raw_body, headers)

      action = WEBHOOK_EVENT_ACTIONS[event.type]
      return nil unless action

      # dispute 家族：无 payment_session（P7-0 F4）——事件语义以 Payment/Charge 为锚，
      # 由 Disputes::HandleProviderEvent 解析，这里只负责验签 + 动作归一分发。
      return { action: action, payment_session: nil, metadata: { stripe_event: event } } if DISPUTE_ACTIONS.include?(action)

      object_id = event.data.object[:id]
      payment_session =
        if object_id.to_s.start_with?('cs_')
          PallasTrade::PaymentSessions::Stripe.find_by(payment_method: self, external_id: object_id)
        else
          # payment_intent.* events carry a `pi_` id. Our session may store the
          # `pi_` id directly (自绘卡字段 PaymentIntent 模式) OR the owning `cs_`
          # Checkout Session id (PRD-20260829 迁移) — resolve either way.
          PallasTrade::PaymentSessions::Stripe.find_by(payment_method: self, external_id: object_id) ||
            find_session_by_payment_intent(object_id)
        end
      return nil unless payment_session

      { action: action, payment_session: payment_session, metadata: { stripe_event: event } }
    end

    # Resolves the local PaymentSession that owns a given Stripe PaymentIntent
    # (used for `payment_intent.*` webhook events after migrating to Checkout
    # Sessions, where the session stores the `cs_` id).
    def find_session_by_payment_intent(payment_intent_id)
      session = send_request { |opts| Stripe::Checkout::Session.list({ payment_intent: payment_intent_id, limit: 1 }, opts) }.first
      return nil unless session

      PallasTrade::PaymentSessions::Stripe.find_by(payment_method: self, external_id: session.id)
    rescue Stripe::StripeError
      nil
    end

    def provider_class
      self.class
    end

    # @param amount_in_cents [Integer] the amount in cents to capture
    # @param payment_source [PallasTrade::CreditCard | PallasTrade::PaymentSource]
    # @param gateway_options [Hash] this is an instance of PallasTrade::Payment::GatewayOptions.to_hash
    def authorize(amount_in_cents, payment_source, gateway_options = {})
      handle_authorize_or_purchase(amount_in_cents, payment_source, gateway_options)
    end

    # @param amount_in_cents [Integer] the amount in cents to capture
    # @param payment_source [PallasTrade::CreditCard | PallasTrade::PaymentSource]
    # @param gateway_options [Hash] this is an instance of PallasTrade::Payment::GatewayOptions.to_hash
    def purchase(amount_in_cents, payment_source, gateway_options = {})
      handle_authorize_or_purchase(amount_in_cents, payment_source, gateway_options)
    end

    # the behavior for authorize and purchase is the same, so we can use the same method to handle both
    def handle_authorize_or_purchase(amount_in_cents, payment_source, gateway_options)
      order_number, payment_number = gateway_options[:order_id].to_s.split('-', 2)

      return failure('Order number is invalid') if order_number.blank?
      return failure('Payment number is invalid') if payment_number.blank?

      order = PallasTrade::Order.where(store_id: stores.ids).find_by(number: order_number)
      return failure('Order was not found') unless order

      payment = order.payments.find_by(number: payment_number)
      return failure('Payment was not found') unless payment

      protect_from_error do
        # eg. payment created via admin
        base_idempotency_key = gateway_options[:idempotency_key]
        payment = ensure_payment_intent_exists_for_payment(
          payment,
          amount_in_cents,
          payment_source,
          idempotency_key: stripe_idempotency_key(base_idempotency_key, 'intent')
        )
        stripe_payment_intent = retrieve_payment_intent(payment.response_code)
        verify_payment_intent_matches!(stripe_payment_intent, amount_in_cents, payment.currency)

        response = if payment_intent_accepted?(stripe_payment_intent)
                     # payment intent is already confirmed via Stripe JS SDK
                     stripe_payment_intent
                   else
                     confirm_payment_intent(
                       stripe_payment_intent.id,
                       idempotency_key: stripe_idempotency_key(base_idempotency_key, 'confirm')
                     )
                   end

        success(response.id, response)
      end
    end

    def credit(amount_in_cents, _source, payment_intent_id, gateway_options = {})
      protect_from_error do
        payload = {
          amount: amount_in_cents,
          payment_intent: payment_intent_id
        }
        originator = gateway_options[:originator]
        # REV-P6-1：优先使用 Refund 稳定 provider_idempotency_key（REV-INV-05）；
        # legacy fallback：refund id 派生（跨 retry 稳定）。
        base_idempotency_key = if originator.respond_to?(:provider_idempotency_key) && originator.provider_idempotency_key.present?
                                 originator.provider_idempotency_key
                               else
                                 "pallastrade-refund-#{originator.id}" if originator&.id
                               end

        response = send_request(idempotency_key: stripe_idempotency_key(base_idempotency_key, 'credit')) do |opts|
          Stripe::Refund.create(payload, opts)
        end

        success(response.id, response)
      end
    end

    def capture(amount_in_cents, payment_intent_id, gateway_options = {})
      protect_from_error do
        stripe_payment_intent = retrieve_payment_intent(payment_intent_id)

        response = if payment_intent_requires_capture?(stripe_payment_intent)
                     capture_payment_intent(
                       payment_intent_id,
                       amount_in_cents,
                       idempotency_key: stripe_idempotency_key(gateway_options[:idempotency_key], 'capture')
                     )
                   elsif stripe_payment_intent.status == 'succeeded'
                     stripe_payment_intent
                   else
                     raise PallasTrade::Core::GatewayError, "Payment intent status is #{stripe_payment_intent.status}"
                   end

        success(response.id, response)
      end
    end

    def void(response_code, _source, gateway_options)
      return failure('Response code is blank') if response_code.blank?

      protect_from_error do
        response = cancel_payment_intent(
          response_code,
          idempotency_key: stripe_idempotency_key(gateway_options[:idempotency_key], 'void')
        )
        success(response.id, response)
      end
    end

    def cancel(payment_intent_id, payment = nil)
      protect_from_error do
        if payment&.completed?
          amount = payment.credit_allowed
          return success(payment_intent_id, {}) if amount.zero?
          # Don't create a refund if the payment is for a shipment, we will create a refund for the whole shipping cost instead
          return success(payment_intent_id, {}) if payment.respond_to?(:for_shipment?) && payment.for_shipment?

          # REV-P6-2：仅登记 durable 退款请求并异步执行（Refunds::Request → ExecuteJob）。
          # Gateway 不再决定业务退款语义，也不在调用上下文内同步调用 PSP（REV-INV-03/15）；
          # 退款失败不再 raise 回滚取消链——以 durable Refund state 记录（REV-P6-6 收敛）。
          PallasTrade::Refunds::Request.call(
            payment: payment, amount: amount,
            reason: PallasTrade::RefundReason.order_canceled_reason,
            refunder_id: payment.order&.canceler_id
          )
          success(payment.response_code, {})
        else
          response = cancel_payment_intent(payment_intent_id)
          success(response.id, response)
        end
      end
    end

    def fetch_or_create_customer(order: nil, user: nil)
      user ||= order&.user
      return nil unless user

      gateway_customers.find_by(user: user) || create_customer(order: order, user: user)
    end

    # Creates a Stripe customer based on the order or user
    #
    # @param order [PallasTrade::Order] the order to use for creating the Stripe customer
    # @param user [PallasTrade::User] the user to use for creating the Stripe customer
    # @return [Stripe::Customer] the created Stripe customer
    def create_customer(order: nil, user: nil)
      payload = build_customer_payload(order: order, user: user)
      response = send_request { |opts| Stripe::Customer.create(payload, opts) }

      customer = gateway_customers.build(user: user, profile_id: response.id)
      customer.save! if user.present?
      customer
    end

    # Updates a Stripe customer based on the order or user
    #
    # @param order [PallasTrade::Order] the order to use for updating the Stripe customer
    # @param user [PallasTrade::User] the user to use for updating the Stripe customer
    # @return [Stripe::Customer] the updated Stripe customer
    def update_customer(order: nil, user: nil)
      user ||= order&.user
      return if user.blank?

      customer = gateway_customers.find_by(user: user)
      return if customer.blank?

      payload = build_customer_payload(order: order, user: user)
      send_request { |opts| Stripe::Customer.update(customer.profile_id, payload, opts) }
    end

    def retrieve_charge(charge_id)
      send_request { |opts| Stripe::Charge.retrieve(charge_id, opts) }
    end

    # PALLAS-CUSTOM: FIN-P4-5 (PRD-20260906-payments-fin-p4-5)
    # Read-only retrieval of a Stripe BalanceTransaction (fee/net authority).
    def retrieve_balance_transaction(balance_transaction_id)
      send_request { |opts| Stripe::BalanceTransaction.retrieve(balance_transaction_id, opts) }
    end

    # PALLAS-CUSTOM: FIN-P4-6 (PRD-20260906-payments-fin-p4-6)
    # Read-only retrieval of a Stripe Refund.
    def retrieve_refund(refund_id)
      send_request { |opts| Stripe::Refund.retrieve(refund_id, opts) }
    end

    # PALLAS-CUSTOM: DSP-P7-2 (PRD-20260911-payments-dsp-p7-2)
    # Read-only retrieval of a Stripe Dispute.
    def retrieve_dispute(dispute_id)
      send_request { |opts| Stripe::Dispute.retrieve(dispute_id, opts) }
    end

    # PALLAS-CUSTOM: FIN-P4-6 (PRD-20260906-payments-fin-p4-6)
    # Read-only provider refund-details contract — normalized financial facts for a single
    # Refund (P4 §37). Resolves the local Refund's transaction_id (re_) to the Stripe Refund
    # and returns { provider_refund_reference:, amount:, currency:, status: } (amount in major units).
    #
    # @param refund [PallasTrade::Refund]
    # @return [Hash]
    # @raise [PallasTrade::Core::GatewayError] when the refund has no provider reference
    # @raise [Stripe::StripeError] on provider/network failure
    def fetch_refund_details(refund:)
      refund_id = refund.transaction_id
      raise PallasTrade::Core::GatewayError, 'Refund has no provider refund reference' if refund_id.blank?

      stripe_refund = retrieve_refund(refund_id)
      {
        provider_refund_reference: stripe_refund.id,
        amount: stripe_refund.amount.to_d / 100,
        currency: stripe_refund.currency.to_s,
        status: stripe_refund.status
      }
    end

    # PALLAS-CUSTOM: REV-P6-8h (PRD-20260908-payments-rev-p6-8h-orphan-amounts-payment-ops)
    # Read-only amount for an ORPHAN (provider-only) refund by provider reference — no local Refund
    # row needed (ReconcileRefund/fetch_refund_details require a local row with transaction_id).
    # @param provider_reference [String] e.g. 're_…'
    # @return [Hash] { amount:, currency: } (amount in major units)
    # @raise [Stripe::StripeError] on provider/network failure (caller degrades per orphan)
    def provider_refund_amount(provider_reference)
      stripe_refund = retrieve_refund(provider_reference)
      {
        amount: stripe_refund.amount.to_d / 100,
        currency: stripe_refund.currency.to_s
      }
    end

    # PALLAS-CUSTOM: DSP-P7-2 (PRD-20260911-payments-dsp-p7-2)
    # Read-only provider dispute-details contract — normalized snapshot for a local Dispute:
    # `{ provider_dispute_reference:, status:, amount:, currency:, reason:, network_reason_code:,
    #    evidence_due_at:, evidence_submitted_at:, has_evidence:, balance_transaction_references:,
    #    observed_at: }`（amount 主单位；零小数货币不除 100）。
    # 只读，零本地写、零 provider mutation；provider 故障由调用方按封闭枚举降级。
    #
    # @param dispute [PallasTrade::Dispute]
    # @return [Hash]
    # @raise [PallasTrade::Core::GatewayError] when the dispute has no provider dispute reference
    # @raise [Stripe::StripeError] on provider/network failure
    def fetch_dispute_details(dispute:)
      reference = dispute.provider_dispute_reference
      raise PallasTrade::Core::GatewayError, 'Dispute has no provider dispute reference' if reference.blank?

      stripe_dispute = retrieve_dispute(reference)
      evidence_details = read_stripe(stripe_dispute, :evidence_details)

      {
        provider_dispute_reference: stripe_dispute.id,
        status: stripe_dispute.status&.to_s,
        amount: PallasTrade::Dispute.normalize_provider_amount(stripe_dispute.amount, stripe_dispute.currency),
        currency: stripe_dispute.currency&.to_s,
        reason: stripe_dispute.reason&.to_s,
        network_reason_code: read_stripe(stripe_dispute, :network_reason_code)&.to_s,
        evidence_due_at: unix_seconds_to_time(read_stripe(evidence_details, :due_by)),
        evidence_submitted_at: unix_seconds_to_time(read_stripe(stripe_dispute, :evidence_submitted_at)),
        has_evidence: read_stripe(evidence_details, :has_evidence),
        balance_transaction_references: stripe_balance_transaction_references(stripe_dispute),
        # DSP-P7-9（FR-P79-03）：BT 明细 + 手续费（扣款与 fee 在**同一条** adjustment BT）
        balance_transaction_details: stripe_balance_transaction_details(stripe_dispute),
        fee_amount: stripe_dispute_fee_amount(stripe_dispute),
        observed_at: Time.current
      }
    end

    # PALLAS-CUSTOM: DSP-P7-9 (PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics)
    # provider **能力矩阵**（只读、零 I/O）：控制台据此渲染/降级（源计划 RV-D10）。
    #
    # @return [Hash]
    def dispute_capabilities
      {
        supported: true,
        reason: nil,
        evidence_submission: true,
        accept_dispute: true,
        fee_capture: true,
        evidence_text_keys: DISPUTE_EVIDENCE_TEXT_KEYS,
        evidence_file_keys: DISPUTE_EVIDENCE_FILE_KEYS
      }
    end

    # PALLAS-CUSTOM: DSP-P7-8 (PRD-20260913-payments-dsp-p7-8)
    # provider 专属**证据类型目录**（Stripe `Dispute.evidence` 字段的受限策展子集，源计划 §68）。
    # 文本键走 `evidence: { <key>: <string> }`；文件键先 `Stripe::File.create` 再把 `file_…` 引用放进同一键。
    DISPUTE_EVIDENCE_TEXT_KEYS = %w[
      customer_name customer_email_address customer_purchase_ip billing_address shipping_address
      product_description uncategorized_text access_activity_log
      shipping_date service_date
      cancellation_policy_disclosure cancellation_rebuttal
      refund_policy_disclosure refund_refusal_explanation
      duplicate_charge_id duplicate_charge_explanation
    ].freeze

    DISPUTE_EVIDENCE_FILE_KEYS = %w[
      customer_communication shipping_documentation receipt
      cancellation_policy refund_policy service_documentation
      duplicate_charge_documentation uncategorized_file
    ].freeze

    def dispute_evidence_catalog
      DISPUTE_EVIDENCE_TEXT_KEYS.map { |key| { key: key, type: 'text', max_length: 20_000 } } +
        DISPUTE_EVIDENCE_FILE_KEYS.map { |key| { key: key, type: 'file' } }
    end

    # PALLAS-CUSTOM: DSP-P7-8 (PRD-20260913-payments-dsp-p7-8)
    # **写**：向 Stripe 提交争议证据（危险操作；调用方已过 permission + confirmation + audit）。
    # 文本 → `Stripe::Dispute.update(evidence: {...})`；文件 → 先上传到 Stripe 再把 file 引用写入同键。
    # **零本地资金副作用**（铁律：资金结果由 webhook 驱动 P7-3 入账 / P7-6 收敛）。
    #
    # @param dispute [PallasTrade::Dispute]
    # @param evidence [Hash] 证据键 → 文本值 / 文件对象（需可读且带 path 或 tempfile）
    # @return [Hash] { provider_reference:, status:, submitted_at:, files: { key => file_ref }, metadata: {} }
    def submit_dispute_evidence(dispute:, evidence:)
      reference = dispute_reference_for!(dispute)
      file_references = {}
      payload = {}

      (evidence || {}).each do |key, value|
        key = key.to_s
        if DISPUTE_EVIDENCE_FILE_KEYS.include?(key)
          file_references[key] = upload_dispute_evidence_file(value)
          payload[key] = file_references[key]
        else
          payload[key] = value.to_s
        end
      end

      stripe_dispute = nil
      if payload.any?
        stripe_dispute = send_request { |opts| Stripe::Dispute.update(reference, { evidence: payload }, opts) }
      end

      {
        provider_reference: read_stripe(stripe_dispute, :id).to_s.presence || reference,
        status: read_stripe(stripe_dispute, :status)&.to_s,
        submitted_at: unix_seconds_to_time(read_stripe(stripe_dispute, :evidence_submitted_at)),
        files: file_references,
        metadata: { 'evidence_keys' => payload.keys.sort }
      }
    end

    # PALLAS-CUSTOM: DSP-P7-8 (PRD-20260913-payments-dsp-p7-8)
    # **写**：接受争议（不可逆）—— Stripe 语义 = 关闭争议（`Dispute.close`）。
    # 本地**不**改 Dispute#state（由 webhook / 收敛推进），只回传归一化回执。
    #
    # @param dispute [PallasTrade::Dispute]
    # @param reason [String] 审计用（不回传 Stripe，Stripe 无对应字段）
    # @return [Hash] { provider_reference:, status:, accepted_at:, metadata: {} }
    def accept_dispute(dispute:, reason: nil)
      reference = dispute_reference_for!(dispute)
      stripe_dispute = send_request { |opts| Stripe::Dispute.close(reference, opts) }

      {
        provider_reference: read_stripe(stripe_dispute, :id).to_s.presence || reference,
        status: read_stripe(stripe_dispute, :status)&.to_s,
        accepted_at: Time.current,
        metadata: { 'reason' => reason.to_s[0, 200] }
      }
    end

    def create_ephemeral_key(customer_id)
      protect_from_error do
        response = send_request { |opts| Stripe::EphemeralKey.create({ customer: customer_id }, opts.merge(stripe_version: Stripe.api_version)) }

        success(response.secret, response)
      end
    end

    def create_setup_intent(customer_id)
      protect_from_error do
        response = send_request { |opts| Stripe::SetupIntent.create({ customer: customer_id, automatic_payment_methods: { enabled: true } }, opts) }

        success(response.client_secret, response)
      end
    end

    def create_tax_calculation(order)
      protect_from_error do
        send_request do |opts|
          Stripe::Tax::Calculation.create(
            PallasTradeStripe::TaxPresenter.new(order: order).call, opts
          )
        end
      end
    end

    def create_tax_transaction(payment_intent_id, tax_calculation_id)
      protect_from_error do
        payload = {
          calculation: tax_calculation_id,
          reference: payment_intent_id,
          expand: ['line_items']
        }

        send_request { |opts| Stripe::Tax::Transaction.create_from_calculation(payload, opts) }
      end
    end

    def attach_customer_to_credit_card(user)
      payment_method_id = user&.default_credit_card&.gateway_payment_profile_id
      return if payment_method_id.blank? || user&.default_credit_card&.gateway_customer_profile_id.present?

      customer = fetch_or_create_customer(user: user)
      return if customer.blank?

      send_request { |opts| Stripe::PaymentMethod.attach(payment_method_id, { customer: customer.profile_id }, opts) }

      user.default_credit_card.update(gateway_customer_profile_id: customer.profile_id, gateway_customer_id: customer.id)
    rescue Stripe::StripeError => e
      Rails.error.report(e, context: { payment_method_id: id, user_id: user.id }, source: 'pallastrade_stripe')
      nil
    end

    def apple_domain_association_file_content
      @apple_domain_association_file_content ||= apple_developer_merchantid_domain_association&.download
    end

    def payment_profiles_supported?
      true
    end

    def default_name
      'Stripe'
    end

    def method_type
      'pallastrade_stripe'
    end

    def payment_icon_name
      'stripe'
    end

    def description_partial_name
      'pallastrade_stripe'
    end

    def custom_form_fields_partial_name
      'pallastrade_stripe'
    end

    def configuration_guide_partial_name
      'pallastrade_stripe'
    end

    # PALLAS-CUSTOM: S1（PRD-20260915-admin §1.1 / FR-010）—— Stripe 专用详情页版面。
    # 页首为「连接」区（凭证 + 环境 + [测试连接] 与最近结果），而非通用版面的诊断卡优先。
    # 注：此前的 `configuration_guide_partial_name`（指向 0 字节 partial）已随 FR-012 删除 ——
    # 不再声明 → 通用/专用版面均不渲染配置指南。
    def provider_page_partial_name
      'pallastrade_stripe'
    end

    def gateway_dashboard_payment_url(payment)
      return if payment.transaction_id.blank?

      "https://dashboard.stripe.com/payments/#{payment.transaction_id}"
    end

    def create_webhook_endpoint
      PallasTradeStripe::CreateGatewayWebhooks.new.call(payment_method: self)
    end

    def create_profile(payment)
      customer = fetch_or_create_customer(order: payment.order)

      payment.source.update(gateway_customer_profile_id: customer.profile_id) if payment.source.present? && customer.present?
    end

    def api_options
      { api_key: preferred_secret_key }
    end

    def send_request(request_options = {})
      yield(api_options.merge(request_options.compact))
    end

    private

    # PALLAS-CUSTOM (2026-09-19, PRD-20260919-checkout-express-always-visible-and-pi-params 真机回归):
    # Checkout Session（ui_mode: elements）顶层载荷白名单。必填事实：
    # `payment_intent_data.billing_details` 不是 Stripe 参数（payment_intent_data 不接受
    # 任何只读字段），dev 真机报 `parameter_unknown: payment_intent_data[billing_details]`。
    CHECKOUT_SESSION_TOP_LEVEL_KEYS = %i[
      after_expiration allow_promotion_codes automatic_tax billing_address_collection cancel_url
      client_reference_id consent_collection currency custom_fields custom_text customer
      customer_creation customer_email customer_update discounts excluded_payment_method_types
      expires_at integration_identifier invoice_creation line_items locale metadata mode
      payment_intent_data payment_method_collection payment_method_configuration
      payment_method_options payment_method_types phone_number_collection recoveries
      redirect_on_completion return_url saved_payment_method_options setup_intent_data
      shipping_address_collection shipping_options submit_type subscription_data success_url
      tax_id_collection ui_mode wallet_options
    ].freeze

    # `payment_intent_data` 内允许下行的字段（Stripe 允许的 PI 创建子集；billing_details 不在内）。
    CHECKOUT_SESSION_PAYMENT_INTENT_DATA_KEYS = %i[
      application_fee_amount capture_method description metadata on_behalf_of receipt_email
      setup_future_usage shipping statement_descriptor statement_descriptor_suffix
      transfer_data transfer_group payment_method_options payment_method_types
    ].freeze

    def assert_legal_checkout_session_payload!(payload)
      unknown = payload.keys.map(&:to_sym) - CHECKOUT_SESSION_TOP_LEVEL_KEYS
      if unknown.any?
        raise ArgumentError, "Stripe Checkout Session payload contains unsupported keys: #{unknown.join(', ')}"
      end

      intent_data = payload[:payment_intent_data] || payload['payment_intent_data']
      return payload if intent_data.blank?

      illegal = intent_data.keys.map(&:to_sym) - CHECKOUT_SESSION_PAYMENT_INTENT_DATA_KEYS
      if illegal.any?
        raise ArgumentError,
              "Stripe Checkout Session payment_intent_data contains unsupported keys: #{illegal.join(', ')} " \
              '(billing_details is read-only and must go through a PaymentMethod)'
      end

      payload
    end

    # DSP-P7-8：写契约共用的 provider 争议引用（缺失即拒绝 —— 不猜引用，不新建远端对象）。
    def dispute_reference_for!(dispute)
      reference = dispute.provider_dispute_reference
      raise PallasTrade::Core::GatewayError, 'Dispute has no provider dispute reference' if reference.blank?

      reference
    end

    # DSP-P7-8：证据文件 → Stripe File（`purpose: dispute_evidence`），返回 `file_…` 引用。
    # 只接受**可读且带 path(/tempfile)** 的上传对象（Stripe SDK 需要真实文件句柄）。
    def upload_dispute_evidence_file(value)
      io = extract_evidence_file_io(value)
      raise PallasTrade::Core::GatewayError, 'Dispute evidence file is missing or not readable' if io.nil?

      stripe_file = send_request { |opts| Stripe::File.create({ purpose: 'dispute_evidence', file: io }, opts) }
      stripe_file.id.to_s
    rescue Stripe::StripeError => e
      raise PallasTrade::Core::GatewayError, filtered_stripe_error_message(e.message)
    end

    def extract_evidence_file_io(value)
      return value.tempfile if value.respond_to?(:tempfile) && value.tempfile.respond_to?(:read)
      return value if value.respond_to?(:read) && value.respond_to?(:path) && value.path.present?

      nil
    end

    # DSP-P7-2：Stripe 对象字段防御性读取（缺失 key 返回 nil，不抛错）。
    def read_stripe(node, key)
      return nil if node.nil?

      node.respond_to?(key) ? node.public_send(key) : nil
    end

    # DSP-P7-2：Stripe unix 秒 → Time（nil/空值不猜）。
    def unix_seconds_to_time(value)
      return nil if value.blank?

      Time.zone.at(value.to_i)
    end

    # DSP-P7-2：dispute.balance_transactions（funds debit / reinstatement 的 BT 引用）。
    def stripe_balance_transaction_references(stripe_dispute)
      list = read_stripe(stripe_dispute, :balance_transactions)
      return [] unless list.respond_to?(:map)

      list.map { |entry| entry.respond_to?(:id) ? entry.id.to_s : entry.to_s }.compact
    end

    # DSP-P7-9（FR-P79-03）：dispute 的 BalanceTransaction 明细（含 fee/net）。
    # 「扣款 + 手续费」在同一条 adjustment BT（P7-0 §9.2 实测），必须拆开读；
    # 字段缺失/非对象条目 → 一律 nil（**不猜**金额）。金额按争议币种做最小单位归一。
    def stripe_balance_transaction_details(stripe_dispute)
      currency = read_stripe(stripe_dispute, :currency)&.to_s
      list = read_stripe(stripe_dispute, :balance_transactions)
      return [] unless list.respond_to?(:map)

      list.map do |entry|
        entry_currency = balance_transaction_field(entry, :currency)&.to_s.presence || currency
        reference = balance_transaction_field(entry, :id)
        reference = entry if reference.blank? && !entry.is_a?(Hash)

        {
          reference: reference.to_s,
          type: balance_transaction_field(entry, :type)&.to_s,
          amount: PallasTrade::Dispute.normalize_provider_amount(balance_transaction_field(entry, :amount), entry_currency),
          fee: PallasTrade::Dispute.normalize_provider_amount(balance_transaction_field(entry, :fee), entry_currency),
          net: PallasTrade::Dispute.normalize_provider_amount(balance_transaction_field(entry, :net), entry_currency),
          currency: entry_currency
        }
      end
    end

    # BT 条目可为 Stripe 对象 / Hash / 纯 id 字符串（webhook 载荷三种都可能）→ 统一防御式读取。
    def balance_transaction_field(entry, key)
      return nil if entry.nil?
      return entry[key] || entry[key.to_s] if entry.is_a?(Hash)

      entry.respond_to?(key) ? entry.public_send(key) : nil
    end

    # 手续费 = adjustment BT 的 fee（正数，取最大值 —— 扣款那条才有 fee，返还那条为 0）。
    # 无 adjustment / 无 fee 字段 → nil（不猜、**不写死金额**）。
    def stripe_dispute_fee_amount(stripe_dispute)
      fees = stripe_balance_transaction_details(stripe_dispute).filter_map do |detail|
        next unless detail[:type].to_s == 'adjustment'

        fee = detail[:fee]&.to_d
        fee if fee&.positive?
      end
      fees.max
    end

    def stripe_idempotency_key(base_key, action)
      return if base_key.blank?

      "#{base_key}-#{action}"
    end

    def verify_payment_intent_matches!(payment_intent, expected_amount, expected_currency)
      amount_matches = payment_intent.amount.to_i == expected_amount.to_i
      currency_matches = payment_intent.currency.to_s.casecmp?(expected_currency.to_s)
      return true if amount_matches && currency_matches

      raise PallasTrade::Core::GatewayError, 'Payment intent amount or currency does not match the payment'
    end

    def validate_secret_key
      Stripe::Refund.list({ limit: 0 }, api_options)
    rescue Stripe::AuthenticationError
      errors.add(:base, 'Secret key is invalid')
    rescue Stripe::PermissionError => e
      errors.add(:base, 'You have provided your publishable key instead of your secret key') if e.error&.code == 'secret_key_required'
    rescue Stripe::StripeError
      errors.add(:base, 'Something went wrong with Stripe. Try again later.')
    end

    def success(authorization, full_response)
      PallasTrade::PaymentResponse.new(true, nil, full_response.as_json, authorization: authorization)
    end

    def failure(error = nil)
      PallasTrade::PaymentResponse.new(false, error)
    end

    def protect_from_error
      yield
    rescue Stripe::StripeError => e
      raise PallasTrade::Core::GatewayError, filtered_stripe_error_message(e.message)
    end

    def filtered_stripe_error_message(message)
      message.to_s
        .gsub(/\b(?:sk|pk)_(?:test|live)_[A-Za-z0-9_]+\b/, '[FILTERED]')
        .gsub(/\bwhsec_[A-Za-z0-9_]+\b/, '[FILTERED]')
        .gsub(/Bearer\s+[^\s]+/i, 'Bearer [FILTERED]')
    end

    def create_webhook_endpoint_async
      return if webhook_keys.any?

      PallasTradeStripe::CreateWebhookEndpointJob.perform_later(id)
    end

    def register_domain
      stores.each do |store|
        RegisterDomainJob.perform_later(store.id, 'store')

        next unless defined?(PallasTrade::CustomDomain)

        store.custom_domains.each do |custom_domain|
          RegisterDomainJob.perform_later(custom_domain.id, 'custom_domain')
        end
      end
    end

    def build_customer_payload(order: nil, user: nil)
      user ||= order&.user
      address = order&.bill_address || user&.bill_address
      name = order&.name || user&.name
      email = order&.email || user&.email

      PallasTradeStripe::CustomerPresenter.new(name: name, email: email, address: address).call
    end

    def verify_webhook_signature(raw_body, headers)
      signature = headers['HTTP_STRIPE_SIGNATURE']
      signing_secrets = webhook_signing_secrets

      signing_secrets.each do |secret|
        return Stripe::Webhook.construct_event(raw_body, signature, secret)
      rescue Stripe::SignatureVerificationError
        next
      end

      raise PallasTrade::PaymentMethod::WebhookSignatureError, 'Invalid webhook signature'
    end

    def webhook_signing_secrets
      secrets = PallasTradeStripe::WebhookKey
        .joins(:payment_methods_webhook_keys)
        .where(payment_methods_webhook_keys: { payment_method_id: id })
        .pluck(:signing_secret)
        .compact

      secrets << ENV['STRIPE_SIGNING_SECRET'] if ENV['STRIPE_SIGNING_SECRET'].present?
      secrets
    end

    # PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance 切片1）——
    # 期望订阅面（业务方案 §69「订阅清单」）：Stripe 后台需启用的事件名集合。
    # `webhook_expected_actions` 由基类映射为本地 action 维度（缺口比对口径）。
    # ⚠️ 必须保持 **public**（运营页/清单服务从实例外部调用；此文件在此处处于 private 区段后方）。
    public

    # @return [Array<String>]
    def webhook_event_subscriptions
      WEBHOOK_EVENT_ACTIONS.keys
    end

    # 本地 action 维度的期望集（去重；与 `PaymentWebhookEvent#action` 同口径）。
    # @return [Array<String>]
    def webhook_expected_actions
      WEBHOOK_EVENT_ACTIONS.values.uniq.map(&:to_s)
    end

    private

    # PALLAS-CUSTOM: D10（PRD-20260915-payments-d10-client-config 切片1）——
    # 声明可下发前台的 publishable 凭据（`Credentials.level` 判级依据，业务方案 §68.4）。
    # 仅 **publishable key** 可下发（Stripe.js 客户端初始化必需，公开值）；
    # `secret_key` 保持 `:password` → 判为 `secret`，永不下发。
    # ⚠️ 键必须是 **symbol**（preferences 以 symbol 存储；string 键会取到 nil）。
    # @return [Array<Symbol>]
    def public_preference_keys
      [:publishable_key]
    end
  end
end
