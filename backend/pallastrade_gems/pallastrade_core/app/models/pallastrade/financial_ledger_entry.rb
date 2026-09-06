# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-2 (PRD-20260905-payments-fin-p4-2)
#
# FinancialLedgerEntry —— CommerceTransaction 级不可变资金账本（Immutable Financial Journal）。
#
# 设计约束：
#   - append-only（FIN-INV-01/07；P4 §8）：amount/currency/source/entry_type/ownership/effective_at
#     创建后禁止原地修改；错误通过 FinancialLedger::Reverse 追加冲销，不 update 历史。
#   - 不可变 enforcement：before_update 拦截常规 save/update；update_columns 重写拦截直接列写
#     （Reverse 原语唯一通过 state/reversed_at 白名单流转，经 mark_reversed!）。
#   - 幂等：idempotency_key UNIQUE（webhook replay/job retry/API retry/recovery retry 不重复 posting）。
#   - posting 输入契约：由 FinancialLedger::Post 消费 FIN-P4-1 FinancialFact（本模型不直接判断
#     payment.completed?，FIN-INV-02/FR-4P1-40）。
#   - entry_type 与 FinancialFact::FACT_TYPES 同名单对齐；ORDER_ALLOCATION(FIN-P4-4)/PSP_FEE/
#     PSP_NET_SETTLEMENT(FIN-P4-5) 预留不激活。
module PallasTrade
  class FinancialLedgerEntry < PallasTrade.base_class
    has_prefix_id :fle

    # FIN-P4-4：ORDER_ALLOCATION 激活（组合资金归属投影，非 cash——FIN-INV-05/AC-4013）；
    # PSP_FEE/PSP_NET_SETTLEMENT 仍预留（FIN-P4-5）。
    ENTRY_TYPES = %w[
      CASH_CAPTURED STORE_CREDIT_APPLIED OFFLINE_PAYMENT_RECORDED REFUND_SUCCEEDED ORDER_ALLOCATION
    ].freeze
    RESERVED_ENTRY_TYPES = %w[PSP_FEE PSP_NET_SETTLEMENT].freeze
    ALL_ENTRY_TYPES = (ENTRY_TYPES + RESERVED_ENTRY_TYPES).freeze
    STATES = %w[posted reversed].freeze

    # 不可变列：创建后禁止任何原地修改
    IMMUTABLE_ATTRIBUTES = %w[
      commerce_transaction_id order_id payment_id refund_id payment_combination_id
      payment_split_id entry_type amount currency idempotency_key effective_at
      provider provider_reference
    ].freeze
    # reversal 流转唯一允许原地更新的列（Reverse 原语内部使用）
    MUTABLE_STATE_ATTRIBUTES = %w[state reversed_at].freeze

    class ImmutableError < StandardError; end

    belongs_to :commerce_transaction, class_name: 'PallasTrade::CommerceTransaction'
    belongs_to :order, class_name: 'PallasTrade::Order', optional: true
    belongs_to :payment, class_name: 'PallasTrade::Payment', optional: true
    belongs_to :refund, class_name: 'PallasTrade::Refund', optional: true
    belongs_to :payment_combination, class_name: 'PallasTrade::PaymentCombination', optional: true
    belongs_to :payment_split, class_name: 'PallasTrade::PaymentSplit', optional: true
    belongs_to :reversal_of, class_name: 'PallasTrade::FinancialLedgerEntry', optional: true,
                             inverse_of: :reversals
    has_many :reversals, class_name: 'PallasTrade::FinancialLedgerEntry',
                         foreign_key: :reversal_of_id, inverse_of: :reversal_of

    validates :commerce_transaction, :currency, :amount, :entry_type, :effective_at, :idempotency_key,
              presence: true
    validates :entry_type, inclusion: { in: ENTRY_TYPES }
    validates :state, inclusion: { in: STATES }
    validates :amount, numericality: true
    validates :idempotency_key, uniqueness: true

    before_update :guard_immutability

    scope :active, -> { where(state: 'posted') }
    scope :by_transaction, ->(transaction) { where(commerce_transaction_id: transaction) }
    scope :by_entry_type, ->(type) { where(entry_type: type) }

    def reversed?
      state == 'reversed'
    end

    # Reverse 原语专用：唯一允许的原地变化（state/reversed_at 白名单）
    def mark_reversed!
      update_columns(state: 'reversed', reversed_at: Time.current)
    end

    # 拦截直接列写（update_columns 绕过 before_update）：非 reversal 状态列一律拒绝。
    # mark_reversed! 仅写 MUTABLE_STATE_ATTRIBUTES 白名单放行。
    def update_columns(*args)
      attrs = args.first
      if attrs.is_a?(Hash)
        forbidden = attrs.keys.map(&:to_s) - MUTABLE_STATE_ATTRIBUTES
        raise ImmutableError,
              "FinancialLedgerEntry is immutable; cannot update_columns attribute(s): #{forbidden.join(', ')}" if forbidden.any?
      end
      super
    end

    # 规范化 posting identity（P4 §13）：同一资金事实（fact）→ 稳定唯一 key。
    # source 取 fact 中最具体的实体（refund > payment > combination > split > order > txn）。
    def self.fact_posting_key(fact)
      source = fact.refund_id.presence || fact.payment_id.presence ||
               fact.payment_combination_id.presence || fact.payment_split_id.presence ||
               fact.order_id.presence || 'txn'
      "fact:#{fact.fact_type}:#{fact.commerce_transaction_id}:#{source}:#{fact.effective_at&.to_i}"
    end

    private

    def guard_immutability
      changed_immutable = changed & IMMUTABLE_ATTRIBUTES
      return if changed_immutable.empty?

      raise ImmutableError,
            "FinancialLedgerEntry is immutable; cannot modify attribute(s): #{changed_immutable.join(', ')}"
    end
  end
end
