module PallasTrade
  class Refund < PallasTrade.base_class
    has_prefix_id :re  # Stripe: re_

    include PallasTrade::Metafields
    include PallasTrade::Metadata
    if defined?(PallasTrade::Security::Refunds)
      include PallasTrade::Security::Refunds
    end

    publishes_lifecycle_events

    # REV-P6-1 —— Durable Refund Execution Aggregate（PRD-REV-P6-1；源文档 REV-P6 §8-11/§56）
    # 语义：Refund Request ≠ Provider Execution ≠ Refund Financial Fact（REV-INV-01）。
    # state 生命周期见源 §9/§10：requested → processing → succeeded/failed/ambiguous → manual_review。
    STATES = %w[requested processing succeeded failed ambiguous manual_review canceled].freeze
    # in-flight 状态（占用 refundable capacity，REV-INV-06 / AC-6007/6008/6009）
    ACTIVE_STATES = %w[requested processing ambiguous].freeze
    # 计入可退额度的状态（succeeded 为已发生资金事实）
    CAPACITY_STATES = (ACTIVE_STATES + %w[succeeded]).freeze
    TERMINAL_STATES = %w[succeeded failed manual_review canceled].freeze
    IDEMPOTENCY_PREFIX = 'refund'

    # 非法状态迁移（REV-P6-1）
    class InvalidTransitionError < StandardError; end

    with_options inverse_of: :refunds do
      belongs_to :payment
      belongs_to :reimbursement, optional: true
    end
    belongs_to :reason, class_name: 'PallasTrade::RefundReason', foreign_key: :refund_reason_id
    belongs_to :refunder, class_name: PallasTrade.admin_user_class.to_s, optional: true

    # REV-P6-1 ownership（可空；创建时可证明才填充——payment→payment_session→commerce_transaction，
    # payment→payment_combination→commerce_transaction，或组合 target split/order。禁止事后猜填，AC-6029）
    belongs_to :commerce_transaction, class_name: 'PallasTrade::CommerceTransaction', optional: true
    belongs_to :target_order, class_name: 'PallasTrade::Order', optional: true
    belongs_to :payment_split, class_name: 'PallasTrade::PaymentSplit', optional: true

    has_many :log_entries, as: :source

    # REV-P6-8a (PRD-REV-P6-8a)：退款的事实 journal 行（immutable financial ledger，Ops 展示只读）
    has_many :journal_entries, class_name: 'PallasTrade::FinancialLedgerEntry', foreign_key: :refund_id

    with_options presence: true do
      validates :payment, :reason
      # REV-P6-1：transaction_id 仅在 SUCCEEDED 时必需（apply_success! 内保证）；
      # failed/ambiguous 行合法地无 provider reference，不再强制 on :update。
      validates :amount, numericality: { greater_than: 0, allow_nil: true }
    end
    validate :amount_is_less_than_or_equal_to_allowed_amount, on: :create, if: :amount
    # REV-P6-3：冻结 payment_split 时 amount 不得超 split 可退额度（captured − refunded，AC-6011/6012）
    validate :amount_within_frozen_split_limit, on: :create, if: -> { payment_split.present? && amount.present? }
    validates :state, inclusion: { in: STATES }

    # REV-P6-8a (PRD-REV-P6-8a)：Ops 列表 ransack 白名单（RansackableAttributes 默认仅 id/name/时间/position）
    self.whitelisted_ransackable_attributes = %w[
      state amount transaction_id requested_at processing_at succeeded_at failed_at ambiguous_at
      last_error_code attempt_count
    ]

    before_create :assign_lifecycle_defaults

    scope :active, -> { where(state: ACTIVE_STATES) }
    scope :capacity_consuming, -> { where(state: CAPACITY_STATES) }
    scope :succeeded, -> { where(state: 'succeeded') }
    scope :failed, -> { where(state: 'failed') }
    scope :ambiguous, -> { where(state: 'ambiguous') }
    scope :non_reimbursement, -> { where(reimbursement_id: nil) }

    # REV-P6-8a (PRD-REV-P6-8a)：store 作用域（Ops 列表）——单订单退款（payment.order）∪ 组合退款
    # （payment.payment_combination；组合 payment 无 order，PaymentCombination 直连 store）。
    # 子查询并集避免 joins 重复行；退款本身无 store_id 列。
    scope :for_store, lambda { |store|
      via_order = joins(payment: :order).where(pallastrade_orders: { store_id: store.id })
      via_combination = joins(payment: :payment_combination)
                        .where(pallastrade_payment_combinations: { store_id: store.id })
      where(id: via_order).or(where(id: via_combination))
    }

    attr_reader :response

    delegate :currency, to: :payment

    # REV-P6-1：状态迁移事件（commit 后发布）→ FinancialLedger::PostRefund 接线。
    after_commit :publish_state_event, on: :update

    # REV-P6-1 状态机（源 §9/§10）。succeeded/failed/manual_review/canceled 为终态；
    # ambiguous 不允许自动重复退款（REV-INV-04）——只允许同 idempotency key 的确定性解决。
    state_machine :state, initial: :requested do
      state :requested
      state :processing
      state :succeeded
      state :failed
      state :ambiguous
      state :manual_review
      state :canceled

      event :start_processing do
        transition requested: :processing
      end
      event :succeed do
        transition %i[requested processing ambiguous] => :succeeded
      end
      event :fail do
        transition %i[requested processing ambiguous] => :failed
      end
      event :mark_ambiguous do
        transition %i[requested processing] => :ambiguous
      end
      event :mark_manual_review do
        transition %i[processing ambiguous] => :manual_review
      end
      # 仅允许 PSP side effect 尚未开始时撤销请求（源 §9）
      event :cancel_request do
        transition requested: :canceled
      end
      # REV-P6-6 预留：provider 重查/人工裁决后的回退执行（同一 provider_idempotency_key）
      event :retry_execution do
        transition %i[failed ambiguous] => :processing
      end

      after_transition to: :processing,    do: :stamp_processing
      after_transition to: :succeeded,     do: :stamp_succeeded
      after_transition to: :failed,        do: :stamp_failed
      after_transition to: :ambiguous,     do: :stamp_ambiguous
      after_transition to: :manual_review, do: :stamp_manual_review
      after_transition to: :canceled,      do: :stamp_canceled
    end

    # P7 (2026-08-28)：payment.order 在组合支付场景为 nil → 从 reimbursement 链推导目标订单
    # REV-P6-1：优先用创建时冻结的 target_order（ownership），其次 legacy 推导。
    def order
      target_order || payment.order || reimbursement_target_order
    end

    def amount=(amount)
      self[:amount] = PallasTrade::LocalizedNumber.parse(amount)
    end

    def money
      PallasTrade::Money.new(amount, currency: currency)
    end
    alias display_amount money

    class << self
      def total_amount_reimbursed_for(reimbursement)
        reimbursement.refunds.succeeded.to_a.sum(&:amount)
      end
    end

    def description
      payment.payment_method.name
    end

    # return items for the refund
    #
    # @return [Array<PallasTrade::ReturnItem>]
    def return_items
      return [] unless reimbursement.present?

      reimbursement.customer_return&.return_items || reimbursement.return_items
    end

    # Returns true if the refund is editable.
    #
    # @return [Boolean]
    def editable?
      target = order
      target.present? && !target.canceled?
    end

    # REV-P6-1：稳定 provider idempotency key（源 §17，REV-INV-05）。
    # prefixed_id 依赖持久化 id（DB 分配）→ 持久化后才有值；Execute claim 时落库。
    #
    # @return [String, nil]
    def execution_idempotency_key
      return nil unless id.present?

      "#{IDEMPOTENCY_PREFIX}:#{prefixed_id}:execute"
    end

    # REV-P6-1：ApplySuccess —— provider 权威成功后本地投影（单事务、幂等、可重放）。
    # 完成：state→succeeded + provider reference 持久化 + PaymentSplit.refunded_amount /
    # Order 投影 + 时间戳 + audit（log entry）。由 Refunds::Execute 在 provider I/O 之后调用。
    #
    # @return [Boolean]
    def apply_success!(authorization:, response: nil)
      return true if succeeded?

      self.transaction_id = authorization
      @response = response
      raise InvalidTransitionError, "Refund #{prefixed_id} cannot succeed from state=#{state}" unless can_succeed?

      succeed!
      update_order
      create_success_log_entry
      true
    end

    # REV-P6-1：明确失败持久化（不 raise 回滚，AC-6002/6009；capacity 释放由 scope 语义表达）
    def record_failure!(code:, message:)
      self.last_error_code = code
      self.last_error_message = message.to_s.truncate(2000)
      return true if %w[failed canceled manual_review].include?(state)

      raise InvalidTransitionError, "Refund #{prefixed_id} cannot fail from state=#{state}" unless can_fail?

      fail!
      true
    end

    # REV-P6-1：未知结果持久化（REV-INV-04/16）——不释放 capacity、不自动重退。
    def record_ambiguous!(code:, message:)
      self.last_error_code = code
      self.last_error_message = message.to_s.truncate(2000)
      return true if %w[ambiguous failed canceled manual_review].include?(state)

      raise InvalidTransitionError, "Refund #{prefixed_id} cannot go ambiguous from state=#{state}" unless can_mark_ambiguous?

      mark_ambiguous!
      true
    end

    # REV-P6-1：人工复核（provider contract 无法自动确定真实资金结果时，源 §10）
    # 注意：不能命名为 mark_manual_review!（与 state_machine bang 事件重名 → 自递归）
    def enter_manual_review!(code: nil, message: nil)
      self.last_error_code = code if code
      self.last_error_message = message.to_s.truncate(2000) if message
      return true if manual_review?

      raise InvalidTransitionError, "Refund #{prefixed_id} cannot go manual_review from state=#{state}" unless can_mark_manual_review?

      mark_manual_review!
      true
    end

    private

    # P7：组合支付退款的目标订单 = reimbursement → customer_return/return_items → inventory_unit.order
    def reimbursement_target_order
      reimbursement&.customer_return&.return_items&.first&.inventory_unit&.order ||
        reimbursement&.return_items&.first&.inventory_unit&.order
    end

    def assign_lifecycle_defaults
      self.requested_at ||= Time.current
      # provider_idempotency_key 依赖持久化 id → 在 Execute claim 时写入（execution_idempotency_key）
    end

    def publish_state_event
      return unless state_previously_changed?

      case state
      when 'succeeded' then publish_event('refund.succeeded')
      when 'failed' then publish_event('refund.failed')
      when 'ambiguous' then publish_event('refund.ambiguous')
      end
    end

    def stamp_processing
      self.processing_at = Time.current
    end

    def stamp_succeeded
      self.succeeded_at = Time.current
    end

    def stamp_failed
      self.failed_at = Time.current
    end

    def stamp_ambiguous
      self.ambiguous_at = Time.current
    end

    def stamp_manual_review
      # manual_review 不新增专用时间列；以 updated_at 为准
    end

    def stamp_canceled
      # canceled 不新增专用时间列；以 updated_at 为准
    end

    def create_success_log_entry
      log_entries.create!(details: @response.to_yaml)
    end

    def amount_is_less_than_or_equal_to_allowed_amount
      if amount > payment.credit_allowed
        errors.add(:amount, :greater_than_allowed)
      end
    end

    # REV-P6-3：冻结组合 split 的退款上限 = split.credit_allowed（captured − refunded，AC-6011）
    def amount_within_frozen_split_limit
      return if amount.to_d <= payment_split.credit_allowed.to_d

      errors.add(:amount, :greater_than_allowed)
    end

    # REV-P6-3：本地成功投影（apply_success! 内调用；与 succeed 同事务）
    # 组合退款：优先命中创建时冻结的 payment_split/target_order（REV-P6-3 冻结语义，消除
    # Reimbursement 链推导歧义 RISK-REV-05）；legacy（无冻结）才走 reimbursement_target_order
    # fallback。只更新目标 split，不碰兄弟单（P4/P7 语义）。
    def update_order
      if payment.order
        payment.order.updater.update
      elsif payment.payment_combination.present?
        target_order = self.target_order || reimbursement_target_order
        if target_order
          split = self.payment_split || target_order.payment_splits.where(payment_id: payment.id).first
          split&.update_columns(refunded_amount: split.refunded_amount.to_f + amount.to_f)
          target_order.updater.update
        end
      end
    end
  end
end
