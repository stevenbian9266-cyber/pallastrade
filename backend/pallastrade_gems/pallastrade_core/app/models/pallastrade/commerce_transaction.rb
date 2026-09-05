# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-1 (PRD-20260904-checkout-txn-p2-1)
#
# CommerceTransaction —— 一次商业交易的 durable orchestration context。
# 它不是 Order/Payment/PaymentAttempt/PaymentCombination；不复制 pricing 域；
# snapshot_data 是不可变交易证据（audit/recovery/reconciliation），不是新的
# 价格计算源（TXN-P2-0 §5.3，INV-09/10）。
#
# 关系：1 ── N TransactionOrder（role: primary|participant）；0..1 PaymentCombination
# （组合支付 strategy 挂载，TXN-P2-2/5 起接）；1 ── N PaymentSession（TXN-P2-2 起）。
# 状态机禁止 payment_confirmed → payment_pending（INV-02/03）。
module PallasTrade
  class CommerceTransaction < PallasTrade.base_class
    has_prefix_id :txn

    include PallasTrade::SingleStoreResource

    self.event_prefix = 'commerce_transaction'
    publishes_lifecycle_events

    PURPOSES = %w[purchase balance_collection combined_payment].freeze

    # TXN-P2-7 (PRD-20260905-payments-txn-p2-7): stuck / needs-attention 语义。
    # 显式"需处理"态恒包含；payment_confirmed/finalizing 超过阈值（默认 1h）
    # 视为卡住（finalize/sweep 未见进展）。
    NEEDS_ATTENTION_STATES = %w[recovery_required manual_review].freeze
    STUCK_STATES = %w[payment_confirmed finalizing].freeze

    belongs_to :store, class_name: 'PallasTrade::Store'
    belongs_to :customer, class_name: PallasTrade.user_class.to_s, optional: true
    belongs_to :payment_combination, class_name: 'PallasTrade::PaymentCombination', optional: true

    has_many :transaction_orders, class_name: 'PallasTrade::TransactionOrder',
                                  foreign_key: :transaction_id, dependent: :destroy,
                                  inverse_of: :commerce_transaction
    has_many :orders, through: :transaction_orders, source: :order
    # TXN-P2-2: transaction 的支付 attempt 会话（1 ── N；legacy/历史 NULL 不回溯）
    has_many :payment_sessions, class_name: 'PallasTrade::PaymentSession',
                                foreign_key: :transaction_id, dependent: :nullify,
                                inverse_of: :commerce_transaction

    validates :store, :currency, :purpose, presence: true
    validates :purpose, inclusion: { in: PURPOSES }
    validates :amount, presence: true,
                       numericality: { greater_than_or_equal_to: 0, allow_nil: true }

    # 业务安全迁移：非 bang 事件返回 false 时转域错误（参考 PaymentCombination 模式）
    class InvalidTransitionError < StandardError
      attr_reader :code

      def initialize(code:, message:)
        @code = code
        super(message)
      end
    end

    # snapshot 冻结后不可覆写（immutable transaction evidence）
    class SnapshotAlreadyFrozen < StandardError; end

    state_machine :state, initial: :created do
      state :created
      state :payment_pending
      state :payment_confirmed
      state :finalizing
      state :completed
      state :canceled
      state :recovery_required
      state :manual_review

      event :start_payment do
        transition created: :payment_pending
      end
      event :confirm_payment do
        transition payment_pending: :payment_confirmed
      end
      event :begin_finalizing do
        transition payment_confirmed: :finalizing
      end
      event :complete do
        transition finalizing: :completed
      end
      event :cancel do
        transition [:created, :payment_pending] => :canceled
      end
      event :mark_recovery_required do
        transition [:payment_confirmed, :finalizing] => :recovery_required
      end
      event :manual_review do
        transition recovery_required: :manual_review
      end
      # TXN-P2-4 (PRD-20260904-payments-txn-p2-4): recovery 出口——
      # UNPAID 复位重试支付；PAID+订单未完成 → 重试 finalize；
      # PAID+订单已完成 → 修复状态至 completed（不重复 finalize）。
      # payment_confirmed → payment_pending 仍物理禁止（INV-02）。
      event :retry_payment do
        transition recovery_required: :payment_pending
      end
      event :retry_finalizing do
        transition recovery_required: :finalizing
      end
      event :repair_completed do
        transition recovery_required: :completed
      end

      after_transition to: :payment_pending,    do: :mark_payment_started
      after_transition to: :payment_confirmed,  do: :mark_payment_confirmed
      after_transition to: :finalizing,         do: :mark_finalizing
      after_transition to: :completed,          do: :mark_completed
      after_transition to: :canceled,           do: :mark_canceled
      after_transition to: :recovery_required,  do: :handle_recovery_required
      after_transition to: :manual_review,      do: :mark_manual_review
    end

    # 冻结 immutable snapshot（TXN-P2-2 Start 调用；本包提供原语）。
    # @raise [SnapshotAlreadyFrozen] 已冻结时
    def snapshot!(checkout_version:, price_version:, fingerprint:, data:)
      raise SnapshotAlreadyFrozen if snapshot_frozen?

      update!(
        checkout_version: checkout_version,
        price_version: price_version,
        snapshot_fingerprint: fingerprint,
        snapshot_data: data
      )
    end

    def snapshot_frozen?
      snapshot_data.present? || snapshot_fingerprint.present?
    end

    # 同一商业意图的活跃交易（供 TXN-P2-2 Start 幂等复用）。
    # @return [PallasTrade::CommerceTransaction, nil]
    def self.active_for_order(order, purpose: nil)
      scope = joins(:transaction_orders).
              where(transaction_orders: { order_id: order.id }).
              where(state: %w[created payment_pending])
      scope = scope.where(purpose: purpose) if purpose.present?
      scope.order(id: :desc).first
    end

    # TXN-P2-7：需要运维关注的交易（stuck visibility）。
    # @param stuck_after [ActiveSupport::Duration] payment_confirmed/finalizing 卡住阈值
    # @return [ActiveRecord::Relation]
    def self.needs_attention(stuck_after: 1.hour)
      stuck_before = Time.current - stuck_after
      where(state: NEEDS_ATTENTION_STATES).
        or(where(state: STUCK_STATES).where(arel_table[:updated_at].lt(stuck_before)))
    end

    # TXN-P2-7：交易 trace 读模型（§58 transaction trace）——聚合时间戳/attempt/
    # last_error/参与者/会话摘要。只读、零副作用。
    # @return [Hash]
    def trace
      participants = transaction_orders.includes(:order).to_a
      sessions = payment_sessions.to_a
      {
        prefixed_id: prefixed_id,
        state: state,
        purpose: purpose,
        currency: currency,
        amount: amount.to_s,
        snapshot_fingerprint: snapshot_fingerprint,
        started_at: started_at&.iso8601,
        payment_confirmed_at: payment_confirmed_at&.iso8601,
        finalizing_at: finalizing_at&.iso8601,
        completed_at: completed_at&.iso8601,
        recovery_required_at: recovery_required_at&.iso8601,
        manual_review_at: manual_review_at&.iso8601,
        canceled_at: canceled_at&.iso8601,
        recovery_attempts: recovery_attempts,
        last_error_class: last_error_class,
        last_error_code: last_error_code,
        last_error_message: last_error_message,
        participants: {
          total: participants.size,
          completed: participants.count { |to| to.order.present? && to.order.completed? },
          roles: participants.map(&:role).tally
        },
        payment_sessions: {
          total: sessions.size,
          by_status: sessions.group_by(&:status).transform_values(&:size)
        }
      }
    end

    # 记录一次恢复尝试的失败元数据（TXN-P2-4 使用；幂等计数）。
    # code/message 为 nil 时保留上一次值（仅记录已知信息）。
    def record_recovery_failure(error_class:, code: nil, message: nil)
      attrs = {
        recovery_attempts: recovery_attempts + 1,
        last_error_class: error_class.to_s
      }
      attrs[:last_error_code] = code if code.present?
      attrs[:last_error_message] = message if message.present?
      update_columns(attrs)
    end

    # 业务安全 bang 方法（非 bang 事件返回 false 时抛域错误，参考 PaymentCombination）
    %i[start_payment confirm_payment begin_finalizing complete cancel
       mark_recovery_required manual_review retry_payment retry_finalizing
       repair_completed].each do |event|
      define_method("#{event}!") do
        unless public_send(event)
          raise InvalidTransitionError.new(
            code: "commerce_transaction_cannot_#{event}",
            message: "Cannot #{event} commerce transaction from state '#{state}'"
          )
        end
        true
      end
    end

    private

    def mark_payment_started
      update_column(:started_at, Time.current) if started_at.nil?
      publish_event('commerce_transaction.payment_started')
    end

    def mark_payment_confirmed
      update_column(:payment_confirmed_at, Time.current)
      publish_event('commerce_transaction.payment_confirmed')
    end

    def mark_finalizing
      update_column(:finalizing_at, Time.current)
      publish_event('commerce_transaction.finalization_started')
    end

    def mark_completed
      update_column(:completed_at, Time.current)
      publish_event('commerce_transaction.completed')
    end

    def mark_canceled
      update_column(:canceled_at, Time.current)
      publish_event('commerce_transaction.canceled')
    end

    def handle_recovery_required
      update_column(:recovery_required_at, Time.current)
      publish_event('commerce_transaction.recovery_required')
    end

    def mark_manual_review
      update_column(:manual_review_at, Time.current)
      publish_event('commerce_transaction.manual_review')
    end
  end
end
