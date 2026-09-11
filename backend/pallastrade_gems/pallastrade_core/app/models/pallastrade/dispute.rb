# frozen_string_literal: true

module PallasTrade
  # PRD-20260911-payments-dsp-p7-1 (DSP-P7-1) / 语义冻结：PRD-20260911-payments-dsp-p7-0
  #
  # `PallasTrade::Dispute` — provider 发起的资金逆转（chargeback / inquiry / warning / representment）
  # 的 durable aggregate。它**不是** Refund：Refund 是商户主动退钱，Dispute 是卡组织/持卡人/PSP 发起。
  #
  # 边界（P7-0 B1–B5，本模型不越界）：
  #   - 不改 CommerceTransaction 状态机（原 txn 保持 completed）
  #   - 不写 order / inventory / payment / 财务账本（本切片零业务副作用）
  #   - 事件进入时**只**改 dispute 域
  #
  # 幂等：`(provider, provider_dispute_reference)` 唯一，`upsert_from_event!` 可重复执行。
  class Dispute < PallasTrade.base_class
    has_prefix_id :dsp

    # provider 语义分类（Stripe 的 warning_* 状态归入 warning）
    KINDS = %w[inquiry warning chargeback retrieval].freeze

    # 域内状态机（P7-0 §7；不直接照搬 provider 状态名）
    STATES = %w[
      opened needs_response accepted submitted under_review
      won lost expired closed manual_review
    ].freeze

    TERMINAL_STATES = %w[accepted won lost expired closed].freeze

    # DSP-P7-2：provider 金额归一（Stripe 等以**最小货币单位**传输；零小数货币即主单位本身）。
    # 单一来源——`Disputes::ProviderPayload` 与网关 fetch 契约均引用本清单，避免两套换算。
    ZERO_DECIMAL_CURRENCIES = %w[bif clp djf gnf jpy kmf krw mga pyg rwf ugx vnd vuv xaf xof xpf].freeze

    # 阶段序（不是逐级邻接矩阵）：provider 会跳级（needs_response → won），因此约束是
    # 「**只能向前**」而不是「只能走相邻状态」；closed 为归档态可从任意状态进入，
    # manual_review 为人工介入态（出入自由）。
    STATE_ORDER = {
      'opened' => 0,
      'needs_response' => 1,
      'submitted' => 2,
      'under_review' => 3,
      'accepted' => 4,
      'won' => 4,
      'lost' => 4,
      'expired' => 4,
      'closed' => 5,
      'manual_review' => 99
    }.freeze

    # 需要人工关注的原因码
    ATTENTION_REASONS = %w[unlinked_payment non_positive_amount invalid_transition].freeze

    class InvalidTransition < StandardError; end

    belongs_to :store, optional: true
    belongs_to :order, optional: true
    belongs_to :payment, optional: true
    belongs_to :commerce_transaction, optional: true
    belongs_to :payment_combination, optional: true

    validates :provider, :provider_dispute_reference, :state, presence: true
    validates :provider_dispute_reference, uniqueness: { scope: :provider }
    validates :state, inclusion: { in: STATES }
    validates :kind, inclusion: { in: KINDS }, allow_nil: true
    # 允许 0（畸形 provider 载荷不阻断事件入库 → 由 attention_reason 标记），负数才拒绝
    validates :amount, numericality: { greater_than_or_equal_to: 0 }
    validates :attention_reason, inclusion: { in: ATTENTION_REASONS }, allow_nil: true

    scope :active, -> { where.not(state: TERMINAL_STATES) }
    scope :terminal, -> { where(state: TERMINAL_STATES) }
    scope :needs_attention, -> { where.not(attention_reason: nil) }

    STATES.each do |state_name|
      define_method("#{state_name}?") { state == state_name }
    end

    def terminal?
      TERMINAL_STATES.include?(state)
    end

    def attention?
      attention_reason.present?
    end

    # DSP-P7-2：零小数货币判定（JPY/KRW 等；此类货币的「最小单位」= 主单位）
    def self.zero_decimal_currency?(currency)
      ZERO_DECIMAL_CURRENCIES.include?(currency.to_s.downcase)
    end

    # DSP-P7-2：provider 最小单位金额 → 域内主单位金额（decimal）。
    # 零小数货币不除 100；nil 原样返回（不猜，由调用方决定 AMBIGUOUS）。
    # @param minor_units [Integer, String, nil]
    # @param currency [String, nil]
    # @return [BigDecimal, nil]
    def self.normalize_provider_amount(minor_units, currency)
      return nil if minor_units.nil?

      amount = minor_units.to_d
      zero_decimal_currency?(currency) ? amount : amount / 100
    end

    # 幂等 upsert：同一 (provider, reference) 只维持一行；nil 值不覆盖既有事实
    # （provider 后续事件常缺字段，例如 closed 事件不带 evidence_details）。
    #
    # @return [PallasTrade::Dispute]
    def self.upsert_from_event!(provider:, reference:, attributes: {})
      dispute = find_or_initialize_by(provider: provider.to_s, provider_dispute_reference: reference.to_s)
      dispute.state = 'opened' if dispute.new_record? && dispute.state.blank?

      attributes.each do |key, value|
        next if value.nil?

        dispute.public_send("#{key}=", value)
      end

      dispute.save!
      dispute
    end

    # 状态迁移（幂等：同状态直接返回 false；不得倒退，非法边抛 InvalidTransition）
    #
    # 允许：同阶段纠偏（won→lost）、向前跳级（needs_response→won）、→ closed（归档）、
    # manual_review 出入自由。拒绝：向后倒退（won→needs_response）与未知状态。
    #
    # @param new_state [String] 目标状态
    # @param at [Time] 生效时间（终态写 resolved_at）
    # @return [Boolean] 是否发生迁移
    # rubocop:disable Naming/PredicateMethod
    def transition_to!(new_state, at: Time.current)
      target = new_state.to_s
      return false if target == state
      raise InvalidTransition, "unknown state: #{target}" unless STATES.include?(target)

      current_rank = STATE_ORDER.fetch(state, 0)
      target_rank = STATE_ORDER.fetch(target, 0)
      allowed = target == 'closed' || target == 'manual_review' || state == 'manual_review' || target_rank >= current_rank
      raise InvalidTransition, "cannot move dispute #{id} from #{state} to #{target}" unless allowed

      assign_attributes(state: target)
      self.resolved_at = at if TERMINAL_STATES.include?(target) && resolved_at.blank?
      save!
      true
    end
    # rubocop:enable Naming/PredicateMethod
  end
end
