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

    # PALLAS-CUSTOM: D16 切片1（PRD-20260916-payments-d16-payment-method-presentation）--
    # 前台展示用的「生效入口」读模型（单一入口：契约投影只调它，禁止在 serializer 各写回落）。
    # 已选项化 → 生效入口的首个（按 position）；未选项化 → 隐式默认入口。
    # @return [Hash]
    def effective_payment_option
      return default_payment_option unless optionized?

      effective_payment_options.first || default_payment_option
    end

    # 入口显示名（前台支付方式行；运营在后台配置的「门店显示名」优先，回落 provider 名）。
    # @param kind [String, nil] 指定入口（D11 后台逐入口展示用）；缺省用生效入口
    # @return [String]
    def option_display_name(kind = nil)
      return effective_payment_option['display_name'].presence || name if kind.blank?

      option = effective_payment_options.find { |candidate| candidate['kind'].to_s == kind.to_s }
      option&.[]('display_name').presence || name
    end

    # 入口稳定标识（前台行键 `option_id`）：`"<prefixed_id>:<kind>"`（确定性、可读、与既有 id 同源）。
    # @param kind [String, nil] 指定入口；缺省用生效入口
    # @return [String]
    def option_identifier(kind = nil)
      resolved_kind = kind.presence || effective_payment_option['kind'] || default_option_kind
      "#{prefixed_id}:#{resolved_kind}"
    end

    # PALLAS-CUSTOM: D7（PRD-20260918-payments-d7-payment-section-express；业务方案 §76.1 / §78-D7）--
    # 入口分组（前台支付区按组渲染与排序）：`card` / `wallet` / `redirect` / `manual`。
    WALLET_OPTION_KINDS = %w[apple_pay google_pay link shop_pay amazon_pay paypal paypal_checkout].freeze

    # @param kind [String, nil] 指定入口；缺省用生效入口
    # @return [String] card / wallet / redirect / manual
    def option_group(kind = nil)
      resolved = (kind.presence || effective_payment_option['kind'] || default_option_kind).to_s
      frontend = option_frontend_kind(resolved)
      return 'manual' if frontend == 'manual'
      return 'wallet' if WALLET_OPTION_KINDS.include?(resolved)
      # `card` 与「inline 入口」（含未选项化 provider 的隐式入口，如 Stripe 的 api_type 入口）均归卡组
      return 'card' if resolved == 'card' || frontend == 'inline'

      'redirect'
    end

    # 入口前端形态（按 kind 取配置；钱包类 kind 未显式配置时回落 `express` —— 不猜成 inline，
    # 否则前台会把钱包入口渲染成卡表单，属「形态错配」）。
    # @param kind [String, nil] 指定入口；缺省用 provider 默认形态
    # @return [String] inline / express / manual
    def option_frontend_kind(kind = nil)
      resolved = kind.to_s.presence
      return default_option_frontend_kind if resolved.blank?

      option = effective_payment_options.find { |candidate| candidate['kind'].to_s == resolved }
      configured = option&.[]('frontend_kind').presence
      return configured if configured.present?
      return 'express' if WALLET_OPTION_KINDS.include?(resolved)

      default_option_frontend_kind
    end

    # 入口级投影（前台支付区「一行一入口」；顺序 = `effective_payment_options` 既有顺序）。
    #
    # ⚠️ 入口集合的**唯一权威**是 `Payments::Availability::Resolver`（与 `PaymentSessions::Start`
    # 同源）：调用方应传 `available_kinds:`（范围规则 / 熔断 / 3DS 闸门过滤后的入口）。不传 =
    # 不过滤（仅用于无订单上下文的只读展示，**不得**作为「可否支付」的依据）。
    #
    # @param available_kinds [Array<String>, nil]
    # @return [Array<Hash>] [{ 'option_id', 'method_key', 'display_name', 'frontend_kind', 'group', 'position' }]
    def payment_option_entries(available_kinds: nil)
      options = effective_payment_options
      if available_kinds
        allowed = Array(available_kinds).map(&:to_s)
        options = options.select { |option| allowed.include?(option['kind'].to_s) }
      end

      options.each_with_index.map do |option, index|
        kind = option['kind'].to_s
        {
          'option_id' => option_identifier(kind),
          'method_key' => kind,
          'display_name' => option_display_name(kind),
          'frontend_kind' => option_frontend_kind(kind),
          'group' => option_group(kind),
          'position' => option['position'].to_i.zero? ? index : option['position'].to_i
        }
      end
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

    # PALLAS-CUSTOM: D11 切片1（PRD-20260916-payments-d11-circuit-breaker-health）--
    # 熔断（软置灰）状态机 API（业务方案 §67.3）。状态存 metadata：
    #   已选项化 provider → `metadata['options'][i]['breaker']`（入口级粒度）
    #   未选项化         → `metadata['breaker']`（该 provider 唯一入口）
    # 字段：opened_at / until / reason / manual / failure_rate / sample_size。
    # 铁律：熔断**零资金副作用** —— 只改 metadata + 写审计；不影响已建会话/已发起的支付。
    BREAKER_KEY = 'breaker'
    # 默认阈值（可经 `metadata['breaker_thresholds']` 覆盖）
    BREAKER_DEFAULTS = {
      'min_samples' => 10,
      'failure_rate_threshold' => 0.5,
      'cooldown_seconds' => 900
    }.freeze

    # @param kind [String, nil] 入口 kind；缺省用生效入口
    # @return [Hash, nil] breaker 状态（字符串键）
    def breaker_state(kind = nil)
      entry = if optionized?
                resolved = (kind.presence || effective_payment_option['kind']).to_s
                option = Array(metadata&.[]('options')).find do |candidate|
                  candidate.is_a?(Hash) && candidate['kind'].to_s == resolved
                end
                option&.dig(BREAKER_KEY)
              else
                metadata&.[](BREAKER_KEY)
              end

      entry.is_a?(Hash) ? entry : nil
    end

    # 软置灰是否**当前**生效。
    #   - 手动置灰（`manual: true`）＝ 粘性：生效至人工解除（忽略 until）
    #   - 自动置灰：到期即视为未置灰（状态行由 Evaluate/SweepJob 清理）
    def soft_disabled?(kind = nil, now: Time.current)
      state = breaker_state(kind)
      return false if state.blank?
      return true if state['manual'] == true

      until_at = PallasTrade::Payments::CircuitBreaker.parse_time(state['until'])
      until_at.present? && until_at > now
    end

    # 写入软置灰状态（幂等：重复写同一入口会覆盖窗口）。
    # @param until_at [Time, nil] nil = 无自动恢复时间（人工解除为准，配合 manual: true）
    # @return [Boolean]
    def soft_disable!(kind: nil, reason:, manual: false, until_at: nil, failure_rate: nil, sample_size: nil)
      state = {
        'opened_at' => Time.current.iso8601,
        'until' => until_at&.iso8601,
        'reason' => reason.to_s.strip.truncate(500),
        'manual' => manual
      }
      state['failure_rate'] = failure_rate unless failure_rate.nil?
      state['sample_size'] = sample_size unless sample_size.nil?

      write_breaker_state(kind, state)
    end

    # 清除软置灰状态（手动解除 / 到期自动解除共用）。
    # @return [Boolean]
    def soft_enable!(kind = nil)
      write_breaker_state(kind, nil)
    end

    # 生效阈值（默认 + metadata 覆盖；字符串/符号键都接受）。
    # @return [Hash] { 'min_samples' =>, 'failure_rate_threshold' =>, 'cooldown_seconds' => }
    def breaker_thresholds
      override = metadata&.[]('breaker_thresholds')
      return BREAKER_DEFAULTS.dup unless override.is_a?(Hash)

      BREAKER_DEFAULTS.merge(override.slice(*BREAKER_DEFAULTS.keys))
    end

    # 写入/清除 metadata 中的 breaker 状态（选项化 → 入口级；否则 provider 级）。
    # ⚠️ 用 `update_columns(private_metadata:)`（D9 已验证范式）：不触发 provider 校验/远端调用，
    #    且 `metadata` 是 `private_metadata` 的 API 别名。
    private def write_breaker_state(kind, state)
      data = (metadata || {}).deep_dup

      if optionized?
        resolved = (kind.presence || effective_payment_option['kind']).to_s
        data['options'] = Array(data['options']).map do |option|
          next option unless option.is_a?(Hash) && option['kind'].to_s == resolved

          option = option.deep_dup
          state.nil? ? option.except(BREAKER_KEY) : option.merge(BREAKER_KEY => state)
        end
      elsif state.nil?
        data.delete(BREAKER_KEY)
      else
        data[BREAKER_KEY] = state
      end

      update_columns(private_metadata: data)
      true
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

    # PALLAS-CUSTOM: PAY-CORE-P0A（PRD-20260920-checkout 支付核心统一 · 切片 P0-A）——
    # 「厂商层」读取口径（业务方案 §2.1/§2.2/§2.3）：能力声明 / 账户配置 / 三态。
    # 本仓**不新建厂商表**：厂商 = 本条 `PaymentMethod` 记录；账户配置存 `metadata['account']`。
    # 三家预接厂商（Stripe / Adyen / PayPal）可各自在网关类定义类方法 `provider_capability`
    # 声明静态能力（国家 / 币种 / 金额区间 / 会话模式）；未声明则由能力目录 + `session_required?` 推导。

    # 厂商静态能力声明（provider 类方法 `provider_capability` 的读取口；未声明 → nil）。
    # @return [Hash, nil]
    def provider_capability_declaration
      klass = self.class
      return nil unless klass.respond_to?(:provider_capability)

      declaration = klass.provider_capability
      declaration.is_a?(Hash) ? declaration : nil
    end

    # 归一后的能力声明（provider 未声明 → 从 `payment_option_catalog` 推导，`source` 标注来源）。
    # @return [Hash]
    def provider_capability
      PallasTrade::Payments::Providers::Config.capability(self)
    end

    # 归一后的账户配置（`metadata['account']`；缺失 → 各维度 nil = 未声明，**不猜**）。
    # @return [Hash]
    def provider_account_config
      PallasTrade::Payments::Providers::Config.account_config(self)
    end

    # 「能力 ∩ 账户」收窄后的生效清单（含 `narrowed` / `basis`，供后台可解释展示）。
    # @return [Hash]
    def provider_effective_scope
      PallasTrade::Payments::Providers::Config.effective(self)
    end

    # 厂商三态（唯一读取口径）：enabled / disabled / suspended。
    # @return [String]
    def provider_state
      PallasTrade::Payments::Providers::State.state(self)
    end

    # 厂商配置诊断（只读）：{ 'ok', 'state', 'issues', 'counts' }。
    # @return [Hash]
    def provider_diagnostics
      PallasTrade::Payments::Providers::Validate.summary(self)
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

    # PALLAS-CUSTOM: D9（PRD-20260915-payments-d9 切片1）—— 环境维度 + 凭据生命周期（业务方案 §68.1/§68.2）。
    # 环境：`test` 不产生真实资金 —— 不进前台列表（Resolver frontend scope），会话/支付打 `test_mode`。
    ENVIRONMENTS = %w[test live].freeze

    validates :environment, inclusion: { in: ENVIRONMENTS }, allow_nil: true

    def test_environment?
      environment == 'test'
    end

    def live_environment?
      !test_environment?
    end

    # 凭据分级（secret / publishable / internal）—— 后台与 API 投影共用。
    def credential_level(key)
      PallasTrade::PaymentMethods::Credentials.level(self, key)
    end

    # `env:NAME` → ENV['NAME']（缺失 nil）；普通值原样返回（引用不落明文）。
    # 兼容 string/symbol 键（preferences 为 YAML 序列化 Hash，provider 声明多为 symbol）。
    def resolved_preference(key)
      raw = preferences[key] if preferences.respond_to?(:[])
      raw = preferences[key.to_sym] if raw.nil?

      PallasTrade::PaymentMethods::Credentials.resolve(raw)
    end

    # 轮换/过期状态（来源：`private_metadata['credentials'][key]`）。
    # @return [Hash] { 'key', 'rotated_at', 'expires_on', 'days_left', 'alert_level' }
    def credential_status(key, now: Time.current)
      entry = credential_metadata(key) || {}
      expires_on = PallasTrade::PaymentMethods::Credentials.parse_date(entry['expires_on'])
      days_left = expires_on ? (expires_on - now.to_date).to_i : nil

      {
        'key' => key.to_s,
        'rotated_at' => entry['rotated_at'].presence&.to_s,
        'expires_on' => expires_on&.iso8601,
        'days_left' => days_left,
        'alert_level' => PallasTrade::PaymentMethods::Credentials.alert_level(days_left)
      }
    end

    # 全部声明的密文型凭据的轮换/过期状态（按 preference schema 顺序）。
    def credentials_status(now: Time.current)
      self.class.password_preference_keys.map { |key| credential_status(key, now: now) }
    end

    # @return [Hash, nil] `private_metadata['credentials'][key]`（非 Hash 一律忽略）
    def credential_metadata(key)
      credentials = metadata&.[]('credentials')
      return nil unless credentials.is_a?(Hash)

      entry = credentials[key.to_s]
      entry.is_a?(Hash) ? entry : nil
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

    # PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance 切片1）——
    # provider 期望收到的事件订阅（业务方案 §69「订阅清单：防漏订」）。
    # 返回 **provider 侧事件名**（如 Stripe `payment_intent.succeeded`）；本地 action 映射见
    # `webhook_expected_actions`。默认空集（不假设任何 provider 的订阅面）。
    # @return [Array<String>]
    def webhook_event_subscriptions
      []
    end

    # 本地 action 维度的期望集（与 `PaymentWebhookEvent#action` 同口径，用于缺口比对）；
    # 默认与 `webhook_event_subscriptions` 一致（provider 事件名 == 本地 action 的 provider）。
    # @return [Array<String>]
    def webhook_expected_actions
      webhook_event_subscriptions.map(&:to_s)
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
