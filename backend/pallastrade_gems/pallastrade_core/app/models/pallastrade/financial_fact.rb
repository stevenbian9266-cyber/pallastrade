# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-1 (PRD-20260905-payments-fin-p4-1)
#
# FinancialFact —— 一个 Payment/Refund 资金事实的**只读值对象**（transient，不落库、无 AR）。
#
# 它表达「本地当前可证明的资金事实」，不是 Payment.state 的镜像（FIN-INV-01/02/03）：
#   - fact_type       描述发生了什么类型的资金事实（cash captured / store credit / offline / refund / none）
#   - status          描述该事实的确认度（FIN-INV-09：无法证明 → AMBIGUOUS，绝不猜）
#   - instrument_class 支付载体分类（PSP cash / store credit / offline / unknown）
#   - commerce_transaction_id 一律指 txn_ 领域对象（P4 §12 命名纪律；禁止用 PSP reference 推断）
#
# 构建者：PallasTrade::FinancialFacts::ResolvePayment / ResolveRefund（只读）。
# 消费约束（FR-4P1-40）：FIN-P4-2 起 Financial Journal posting 只能消费本 contract，
# 禁止在各 posting service 重新复制 payment.completed? / provider-specific 判定。
module PallasTrade
  class FinancialFact
    # status 最小集合（FR-4P1-02）
    STATUSES = %w[
      CONFIRMED AUTHORIZED_ONLY UNPAID AMBIGUOUS NOT_APPLICABLE UNSUPPORTED
    ].freeze

    # fact_type 最小集合（FR-4P1-03；ORDER_ALLOCATION 于 FIN-P4-4 激活——FR-4P4-01）
    # DSP-P7-3（FR-P73-01）：争议域 5 个事实类型与 `Disputes::DisputeFact::FACT_TYPES` **同名单对齐**
    #   —— 仅 FUNDS_WITHDRAWN / FUNDS_REINSTATED 为**现金事实**（激活 entry_type）；
    #   OPENED / WON / LOST 为**非现金事实**（永不入账，防双记——FR-P73-02）。
    FACT_TYPES = %w[
      CASH_CAPTURED STORE_CREDIT_APPLIED OFFLINE_PAYMENT_RECORDED REFUND_SUCCEEDED ORDER_ALLOCATION
      DISPUTE_OPENED DISPUTE_FUNDS_WITHDRAWN DISPUTE_FUNDS_REINSTATED DISPUTE_WON DISPUTE_LOST
      NONE
    ].freeze

    # instrument class（FR-4P1-05）
    INSTRUMENT_CLASSES = %w[PSP_CASH STORE_CREDIT OFFLINE UNKNOWN].freeze

    STATUSES.each { |s| const_set(s, s) }
    FACT_TYPES.each { |t| const_set(t, t) }
    INSTRUMENT_CLASSES.each { |i| const_set(i, i) }

    # 金额/币种字段的“来源冲突 → AMBIGUOUS”语义见 ResolvePayment（FR-4P1-18）。
    ATTRIBUTES = %i[
      fact_type status amount currency instrument_class
      commerce_transaction_id order_id payment_id refund_id dispute_id
      payment_session_id payment_combination_id payment_split_id
      provider provider_payment_reference provider_refund_reference provider_dispute_reference
      effective_at evidence reason_code
    ].freeze

    attr_reader(*ATTRIBUTES)

    # @param attrs [Hash] 仅接受 ATTRIBUTES 白名单键；对象构造后 freeze（不可变）
    def initialize(**attrs)
      unknown = attrs.keys - ATTRIBUTES
      raise ArgumentError, "Unknown FinancialFact attributes: #{unknown.join(', ')}" if unknown.any?

      ATTRIBUTES.each { |a| instance_variable_set("@#{a}", attrs.fetch(a, nil)) }
      freeze
    end

    def confirmed?
      status == CONFIRMED
    end

    def ambiguous?
      status == AMBIGUOUS
    end

    def unsupported?
      status == UNSUPPORTED
    end

    def cash_captured?
      fact_type == CASH_CAPTURED && status == CONFIRMED
    end

    def refund_succeeded?
      fact_type == REFUND_SUCCEEDED && status == CONFIRMED
    end

    # FIN-P4-4：ORDER_ALLOCATION = 组合资金对成员订单的归属投影（非 cash inflow，FIN-INV-05/AC-4013）。
    def allocation?
      fact_type == ORDER_ALLOCATION
    end

    # 该事实是否已拥有确定性资金结果（供 FIN-P4-2 posting 决定是否可入账）。
    def postable_cash_fact?
      confirmed? && %w[CASH_CAPTURED STORE_CREDIT_APPLIED OFFLINE_PAYMENT_RECORDED REFUND_SUCCEEDED].include?(fact_type)
    end

    def to_h
      ATTRIBUTES.index_with { |a| public_send(a) }
    end

    def as_json(*)
      to_h
    end
  end
end
