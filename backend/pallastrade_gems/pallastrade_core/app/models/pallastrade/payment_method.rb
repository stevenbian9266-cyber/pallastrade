module PallasTrade
  class PaymentMethod < PallasTrade.base_class
    has_prefix_id :pm  # Stripe: pm_

    acts_as_paranoid
    acts_as_list

    include PallasTrade::SingleStoreResource
    include PallasTrade::Metafields
    include PallasTrade::Metadata
    include PallasTrade::DisplayOn
    if defined?(PallasTrade::Security::PaymentMethods)
      include PallasTrade::Security::PaymentMethods
    end
    # Multi-store sharing moved to the pallastrade_multi_store extension in 5.6.
    include PallasTrade::LegacyMultiStoreSupport unless defined?(PallasTradeMultiStore)

    scope :active,    -> { where(active: true).order(position: :asc) }
    scope :available, -> { active.where(display_on: [:front_end, :back_end, :both]) }
    scope :store_credit, -> { where(type: 'PallasTrade::PaymentMethod::StoreCredit') }

    after_initialize :set_name, if: :new_record?

    validates :name, presence: true
    validates :store, presence: true, unless: -> { PallasTrade::Config[:disable_store_presence_validation] }
    normalizes :name, with: ->(value) { value&.to_s&.squish&.presence }

    belongs_to :store, class_name: 'PallasTrade::Store'

    has_many :payments, class_name: 'PallasTrade::Payment', inverse_of: :payment_method, dependent: :nullify
    has_many :credit_cards, class_name: 'PallasTrade::CreditCard', dependent: :destroy # CCs are soft deleted

    has_many :payment_sessions, class_name: 'PallasTrade::PaymentSession', dependent: :destroy
    has_many :payment_setup_sessions, class_name: 'PallasTrade::PaymentSetupSession', dependent: :destroy
    has_many :gateway_customers, class_name: 'PallasTrade::GatewayCustomer', dependent: :destroy

    def self.providers
      PallasTrade.payment_methods
    end

    def provider_class
      raise ::NotImplementedError, 'You must implement provider_class method for this gateway.'
    end

    # The class that will process payments for this payment type, used for @payment.source
    # e.g. CreditCard in the case of a the Gateway payment type
    # nil means the payment method doesn't require a source e.g. check
    def payment_source_class
      return unless source_required?

      raise ::NotImplementedError, 'You must implement payment_source_class method for this gateway.'
    end

    # The class used for payment sessions with this payment method.
    # Override in gateway subclasses to provide a provider-specific session class
    # that inherits from PallasTrade::PaymentSession (STI).
    # nil means the payment method doesn't support payment sessions.
    def payment_session_class
      nil
    end

    # Creates a payment session via the provider.
    # Override in gateway subclasses to implement provider-specific session creation.
    def create_payment_session(order:, amount: nil, external_data: {})
      raise ::NotImplementedError, 'You must implement create_payment_session method for this gateway.'
    end

    # Updates an existing payment session via the provider.
    # Override in gateway subclasses to implement provider-specific session updates.
    def update_payment_session(payment_session:, amount: nil, external_data: {})
      raise ::NotImplementedError, 'You must implement update_payment_session method for this gateway.'
    end

    # Completes a payment session via the provider.
    # Override in gateway subclasses to implement provider-specific session completion.
    #
    # Responsibilities:
    # - Verify payment status with the provider
    # - Create/update the PallasTrade::Payment record
    # - Patch order data from provider (e.g. wallet billing address)
    # - Transition payment session to completed/failed
    #
    # Must NOT complete the order — that is handled by Carts::Complete
    # (called by the frontend or by the webhook handler).
    def complete_payment_session(payment_session:, params: {})
      raise ::NotImplementedError, 'You must implement complete_payment_session method for this gateway.'
    end

    # PALLAS-CUSTOM: TXN-P2-3 (PRD-20260904-payments-txn-p2-3)
    # Read-only provider status contract. Queries the provider for the current
    # authoritative status of a payment session WITHOUT mutating any local
    # state (no Payment creation, no state transitions). Consumed by
    # PallasTrade::Transactions::PaymentFactResolver (money-fact resolution).
    #
    # @param payment_session [PallasTrade::PaymentSession]
    # @return [Hash] normalized status:
    #   { status: Symbol, amount_cents: Integer, currency: String, provider_reference: String }
    #   status ∈ :paid | :unpaid | :processing | :requires_capture |
    #            :requires_action | :canceled | :failed | :expired
    # @raise [::NotImplementedError] when the gateway has no read-only contract
    # @raise [PallasTrade::Core::GatewayError] on provider/network failure
    def fetch_payment_status(payment_session:)
      raise ::NotImplementedError, 'You must implement fetch_payment_status method for this gateway.'
    end

    # PALLAS-CUSTOM: FIN-P4-5 (PRD-20260906-payments-fin-p4-5)
    # Read-only provider financial-details contract (P4 §30/§31). Queries the provider for
    # authoritative financial facts of a payment session WITHOUT mutating any local state
    # (no Payment creation, no state transitions) and returns a normalized Hash that
    # `PallasTrade::FinancialFacts::ProviderFinancialDetails.from_hash` can consume.
    #
    # Output fields (P4 §31): provider_payment_reference (pi_…), provider_charge_reference (ch_…),
    #   provider_balance_transaction_reference (txn_…), provider_refund_references (re_…[]),
    #   gross_amount/gross_currency, refund_total/refund_currency, fee_amount/fee_currency,
    #   net_amount/net_currency, settlement_status, observed_at, raw_reference.
    #   fee/net/refund_total are nullable when not provable (un-captured / no balance transaction) — no guessing.
    # Consumed by FIN-P4-6 Source Reconciliation. fee/net are reconciliation facts, never Journal entries.
    #
    # @param payment_session [PallasTrade::PaymentSession]
    # @return [Hash] normalized financial details (see above)
    # @raise [::NotImplementedError] when the gateway has no read-only financial-details contract
    # @raise [PallasTrade::Core::GatewayError] on provider/network failure
    def fetch_financial_details(payment_session:)
      raise ::NotImplementedError, 'You must implement fetch_financial_details method for this gateway.'
    end

    # PALLAS-CUSTOM: FIN-P4-6 (PRD-20260906-payments-fin-p4-6)
    # Read-only provider refund-details contract — authoritative financial facts for a single
    # Refund (P4 §37: local Refund ↔ provider Refund; amount/currency/reference check). No local
    # writes, no provider mutation. Consumed by Reconciliations::ReconcileRefund.
    #
    # @param refund [PallasTrade::Refund]
    # @return [Hash] { provider_refund_reference:, amount:, currency:, status: }
    # @raise [::NotImplementedError] when the gateway has no read-only refund contract
    # @raise [PallasTrade::Core::GatewayError] when refund has no provider reference / on provider failure
    def fetch_refund_details(refund:)
      raise ::NotImplementedError, 'You must implement fetch_refund_details method for this gateway.'
    end

    # PALLAS-CUSTOM: REV-P6-8h (PRD-20260908-payments-rev-p6-8h-orphan-amounts-payment-ops)
    # Read-only per-provider-refund amount contract for ORPHAN (provider-only) refunds: given a
    # provider refund reference (e.g. Stripe re_…), return { amount:, currency: } in major units.
    # Base returns nil — capability is detected by method owner != PaymentMethod (same pattern as
    # CaptureEvidencePolicy#implements_financial_details?), so gateways without real orphan
    # semantics (e.g. Bogus, whose references are locally derived) naturally degrade to nil.
    # Never mutates provider/local state. Implementations raise provider errors for the caller
    # to degrade per item (OrphanPairing rescues per orphan).
    #
    # @param provider_reference [String] provider refund id
    # @return [Hash, nil] { amount:, currency: } or nil when not supported/not provable
    def provider_refund_amount(provider_reference)
      nil
    end

    # PALLAS-CUSTOM: DSP-P7-2 (PRD-20260911-payments-dsp-p7-2)
    # Read-only provider dispute-details contract — authoritative provider snapshot for a single
    # Dispute (P7-0 §7): status / amount / currency / reason / evidence window / balance-transaction
    # references. No local writes, no provider mutation. Consumed by `Disputes::ResolveFact`, and
    # used as the O1–O5 evidence-collection tool for the P7 line. Capability detection follows the
    # `fetch_refund_details` pattern (method owner != base PaymentMethod).
    #
    # @param dispute [PallasTrade::Dispute]
    # @return [Hash] normalized provider snapshot (amount in major units)
    # @raise [::NotImplementedError] when the gateway has no read-only dispute contract
    # @raise [PallasTrade::Core::GatewayError] when the dispute has no provider reference
    # @raise [Stripe::StripeError] on provider/network failure (caller degrades)
    def fetch_dispute_details(dispute:)
      raise ::NotImplementedError, 'You must implement fetch_dispute_details method for this gateway.'
    end

    # PALLAS-CUSTOM: DSP-P7-8 (PRD-20260913-payments-dsp-p7-8)
    # **写**契约：向 provider 提交争议证据（危险操作之一；调用方必须已过 permission + confirmation + audit）。
    # 基类 raise → 能力由「类级 method owner ≠ 基类」与 `#dispute_evidence_catalog` 共同探测（零 I/O）。
    # 实现方约定：evidence = { 证据键 => 文本值 | 文件对象 }；返回归一化回执
    # `{ provider_reference:, status:, submitted_at:, files: { key => provider_file_ref }, metadata: {} }`。
    # 实现方**不得**触碰本地资金/订单/库存（铁律：资金结果由 webhook 驱动）。
    #
    # @param dispute [PallasTrade::Dispute]
    # @param evidence [Hash]
    # @return [Hash] 归一化回执
    # @raise [::NotImplementedError] when the gateway has no write contract
    # @raise [PallasTrade::Core::GatewayError] when the dispute has no provider reference
    def submit_dispute_evidence(dispute:, evidence:)
      raise ::NotImplementedError, 'You must implement submit_dispute_evidence method for this gateway.'
    end

    # PALLAS-CUSTOM: DSP-P7-8 (PRD-20260913-payments-dsp-p7-8)
    # **写**契约：接受争议（不可逆；provider 侧通常等于关闭争议）。同 submit_dispute_evidence 的三件套约束。
    #
    # @param dispute [PallasTrade::Dispute]
    # @param reason [String]
    # @return [Hash] 归一化回执 `{ provider_reference:, status:, accepted_at:, metadata: {} }`
    def accept_dispute(dispute:, reason: nil)
      raise ::NotImplementedError, 'You must implement accept_dispute method for this gateway.'
    end

    # PALLAS-CUSTOM: DSP-P7-8 (PRD-20260913-payments-dsp-p7-8)
    # provider 专属**证据类型目录**（源计划 §68）；空目录 = 该网关不支持证据提交。
    # 条目形状：`{ key:, type: 'text'|'file', max_length:, required: }`（核心不内置任何 provider 字段名）。
    #
    # @return [Array<Hash>]
    def dispute_evidence_catalog
      []
    end

    # PALLAS-CUSTOM: DSP-P7-9 (PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics)
    # provider **能力矩阵**（只读、零 I/O）：控制台据此渲染/降级（源计划 RV-D10）。
    # 基类返回 `UNSUPPORTED` 形态——无契约的 provider **不得被猜成支持**；适配器覆写为真实矩阵。
    #
    # @return [Hash] { supported:, reason:, evidence_submission:, accept_dispute:, fee_capture:,
    #                  evidence_text_keys:, evidence_file_keys: }
    def dispute_capabilities
      {
        supported: false,
        reason: 'unsupported_provider',
        evidence_submission: false,
        accept_dispute: false,
        fee_capture: false,
        evidence_text_keys: [],
        evidence_file_keys: []
      }
    end

    # Parses an incoming webhook payload from the payment provider.
    # Override in gateway subclasses to implement provider-specific webhook parsing.
    #
    # @param raw_body [String] the raw request body
    # @param headers [Hash] the request headers
    # @return [Hash, nil] normalized result or nil for unsupported events
    #   { action: :captured/:authorized/:failed/:canceled,
    #     payment_session: <PallasTrade::PaymentSession>,
    #     metadata: {} }
    # @raise [PallasTrade::PaymentMethod::WebhookSignatureError] if signature is invalid
    def parse_webhook_event(raw_body, headers)
      raise ::NotImplementedError, 'You must implement parse_webhook_event method for this gateway.'
    end

    # Returns the webhook URL for this payment method.
    # @return [String, nil]
    def webhook_url
      return nil unless store

      "#{store.url_or_custom_domain}/api/v3/webhooks/payments/#{prefixed_id}"
    end

    class WebhookSignatureError < StandardError; end

    # Whether this payment method supports setup sessions (saving payment methods for future use).
    # Override in gateway subclasses that support tokenization without a payment.
    def setup_session_supported?
      false
    end

    # The class used for payment setup sessions with this payment method.
    # Override in gateway subclasses to provide a provider-specific session class.
    def payment_setup_session_class
      nil
    end

    # Creates a payment setup session via the provider for saving a payment method.
    # Override in gateway subclasses to implement provider-specific setup session creation.
    def create_payment_setup_session(customer:, external_data: {})
      raise ::NotImplementedError, "#{self.class.name} does not implement #create_payment_setup_session"
    end

    # Completes a payment setup session via the provider.
    # Override in gateway subclasses to implement provider-specific setup session completion.
    def complete_payment_setup_session(setup_session:, params: {})
      raise ::NotImplementedError, "#{self.class.name} does not implement #complete_payment_setup_session"
    end

    def method_type
      type.demodulize.downcase
    end

    def default_name
      self.class.name.demodulize.titleize.gsub(/Gateway/, '').strip
    end

    def payment_icon_name
      type.demodulize.gsub(/(^PallasTrade::Gateway::|Gateway$)/, '').downcase.gsub(/\s+/, '').strip
    end

    def self.find_with_destroyed(*args)
      unscoped { find(*args) }
    end

    def confirmation_required?
      false
    end

    def payment_profiles_supported?
      false
    end

    def source_required?
      true
    end

    def session_required?
      false
    end

    def show_in_admin?
      true
    end

    # Custom gateways should redefine this method. See Gateway implementation
    # as an example
    def reusable_sources(_order)
      []
    end

    def auto_capture?
      auto_capture.nil? ? PallasTrade::Config[:auto_capture] : auto_capture
    end

    def supports?(_source)
      true
    end

    def cancel(_response)
      raise ::NotImplementedError, 'You must implement cancel method for this payment method.'
    end

    def store_credit?
      self.class == PallasTrade::PaymentMethod::StoreCredit
    end

    # Custom PaymentMethod/Gateway can redefine this method to check method
    # availability for concrete order.
    def available_for_order?(order)
      !order.covered_by_store_credit?
    end

    def available_for_store?(store)
      return true if store.blank?

      store_id == store.id
    end

    def public_preferences
      public_preference_keys.each_with_object({}) do |key, hash|
        hash[key] = preferences[key]
      end
    end

    # PALLAS-CUSTOM: PAY-OPT-1 (PRD-20260915-admin 支付配置选项化，切片1)
    # 前台入口（PaymentOption）: 一个 provider 可配多个「入口」（method），各自独立启停/排序/命名。
    # 过渡期不建表 —— 入口存 `metadata["options"]`（业务方案 §65 / §74 的阶段一形态）：
    #
    #   metadata = {
    #     "optionized" => true,                    # 是否已转为选项化（决定 0 options 的语义）
    #     "options" => [
    #       { "kind" => "card", "active" => true, "position" => 1, "frontend_kind" => "inline" },
    #       { "kind" => "apple_pay", "active" => true, "position" => 2, "frontend_kind" => "express" }
    #     ]
    #   }
    #
    # 门控语义（§0.1-12）：
    #   optionized=false → 0 options 视作「未迁移」→ 回落 1 个默认入口（行为与今天一致）
    #   optionized=true  → 0 options 就是 0 个前台入口（配置语义，禁止自动兜底）
    #
    # ⚠️ 命名避让：`PallasTrade::Gateway#options` 已存在（网关偏好项），因此本能力一律
    # 使用 `payment_option(s)` 前缀命名，避免网关型 provider（Stripe / Bogus…）上被覆盖。
    OPTIONIZED_KEY = 'optionized'
    OPTIONS_KEY = 'options'

    # 归一化后的入口列表（未筛选/未排序）；非法结构一律忽略，保证只读安全。
    def payment_options
      raw = metadata&.[](OPTIONS_KEY)
      return [] unless raw.is_a?(Array)

      raw.filter_map do |entry|
        next unless entry.is_a?(Hash)

        normalized = entry.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }
        next if normalized['kind'].blank?

        normalized
      end
    end

    # 已启用入口，按 position 升序（position 相同保持配置顺序）。
    def available_payment_options
      payment_options.select { |option| option['active'] != false }
                     .each_with_index.sort_by { |option, index| [option['position'].to_i, index] }
                     .map(&:first)
    end

    def payment_option_for(kind)
      payment_options.find { |option| option['kind'] == kind.to_s }
    end

    def optionized?
      metadata&.[](OPTIONIZED_KEY) == true
    end

    # 生效入口：已选项化 → 仅用配置的；未选项化 → 有配置用配置，否则回落默认入口。
    def effective_payment_options
      available = available_payment_options
      return available if optionized? || available.any?

      [default_payment_option]
    end

    # 是否应出现在前台列表：已选项化且没有任何可用入口 → 不出现。
    def frontend_visible?
      return true unless optionized?

      available_payment_options.any?
    end

    # 未选项化 provider 的隐式默认入口（与今天的单入口行为一致）。
    def default_payment_option
      {
        'kind' => default_option_kind,
        'active' => true,
        'position' => 0,
        'display_name' => name,
        'frontend_kind' => default_option_frontend_kind
      }
    end

    # 默认 kind：优先用网关的 `api_type`（stripe / adyen / paypal…），否则从类名推导。
    def default_option_kind
      return api_type.to_s if respond_to?(:api_type) && api_type.present?

      type.to_s.demodulize.underscore
    rescue StandardError
      type.to_s.demodulize.underscore
    end

    # 前端形态：会话类 → inline（自绘壳/官方字段）；非会话类 → manual（仅说明文案）。
    def default_option_frontend_kind
      session_required? ? 'inline' : 'manual'
    end

    # PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915-admin 切片3）—— 能力目录（Capability Catalog）：
    # 该 provider **声明支持**的前台入口清单（业务方案 §63.3 / §65.2），provider gem 可覆盖。
    # 条目：{ 'kind' =>, 'frontend_kind' =>, 'display_name' => }；不含状态（启停/排序在 options 里）。
    # 默认只有隐式默认入口 —— 未声明能力的 provider 行为不变（零回归）。
    def payment_option_catalog
      [
        {
          'kind' => default_option_kind,
          'frontend_kind' => default_option_frontend_kind,
          'display_name' => name
        }
      ]
    end

    # PALLAS-CUSTOM: D8（PRD-20260915-payments-d8 切片1）—— 入口「适用范围」读取（业务方案 §66.2）。
    # @return [Hash, nil] 归一后的 rule_set；nil = 不限（无规则 / 非法配置一律视同不限）
    def payment_option_rule_set(kind)
      option = payment_option_for(kind)
      return nil if option.nil?

      PallasTrade::Payments::Availability::RuleSet.normalize(option['rule_set'])
    end

    # 后台摘要（labels: (dimension, value) → 展示名 的可选解析器；缺省用 default_option_scope_labels）。
    # @return [String] 如 "市场: EU · 币种: EUR"；无规则 → "全部"
    def payment_option_scope_summary(kind, labels: nil)
      option = payment_option_for(kind)
      return PallasTrade::Payments::Availability::RuleSet.summary(nil) if option.nil?

      PallasTrade::Payments::Availability::RuleSet.summary(
        option['rule_set'], labels: labels || default_option_scope_labels
      )
    end

    # D8（切片2）—— 摘要默认展示名：market/zone 回记录名（找不到回原值），country/currency 本就是展示值。
    def default_option_scope_labels
      lambda do |dimension, value|
        case dimension
        when 'market' then store&.markets&.find_by(id: value)&.name || value
        when 'zone' then PallasTrade::Zone.find_by(id: value)&.name || value
        else value
        end
      end
    end

    # PALLAS-CUSTOM: PAY-OPT-1（切片3）—— 凭证体检钩子（Test connection 的远端探测）。
    # provider gem 可选覆盖，执行一次**只读**探测（不得产生资金 / 配置副作用；不得落明文凭证）。
    # 契约：
    #   nil                     → 该 provider 无远端探测能力（仅做本地凭证体检）
    #   true / false            → 探测通过 / 未通过（无附加说明）
    #   { ok:, code:, message: } → 结构化结果（code 为 provider 自定义短码，如 invalid_credentials）
    # 抛错 → 由 PallasTrade::PaymentMethods::TestConnection 归类（网络类 → network_unreachable）。
    def test_connection
      nil
    end

    protected

    def public_preference_keys
      []
    end

    def set_name
      self.name ||= default_name
    end
  end
end
