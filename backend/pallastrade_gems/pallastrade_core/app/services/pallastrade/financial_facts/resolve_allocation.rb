# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-4 (PRD-20260906-payments-fin-p4-4)
#
# FinancialFacts::ResolveAllocation —— 把组合支付的一个 PaymentSplit 解析为标准 ORDER_ALLOCATION
# FinancialFact（FR-4P4-02）。
#
# 语义（P4 §21/§22/§23 + FIN-INV-05）：
#   - PaymentSplit = allocation source of truth；ORDER_ALLOCATION = 这笔组合资金对成员订单的
#     **归属投影（immutable）**，不是额外 cash inflow（AC-4013）。
#   - 可证明（combination + combination.commerce_transaction + captured_amount > 0）→
#     CONFIRMED ORDER_ALLOCATION（amount = split.captured_amount；order_id = split.order；
#     payment_split_id = split；currency = split.currency）。
#   - 不可证明（无组合 / 组合无 txn（legacy Strangler）/ captured=0）→ 表达为不可 post 的 fact
#     （status=AMBIGUOUS，reason_code 区分）——不猜、无部分记录（FIN-INV-09/FR-4P4-08）。
#
# 只读边界（FR-4P4-09）：本服务不创建/更新/删除任何记录（含 split/combination/order），
# 不改 state machine，不写 Journal。
module PallasTrade
  module FinancialFacts
    class ResolveAllocation
      prepend PallasTrade::ServiceModule::Base

      # @param split [PallasTrade::PaymentSplit]
      # @return [PallasTrade::ServiceModule::Result]
      #   success(PallasTrade::FinancialFact) —— “无法证明”经 fact.status=AMBIGUOUS 表达，不是 failure
      #   （failure 仅用于输入缺失）
      def call(split:)
        return failure(nil, 'Payment split not found') if split.nil?

        success(build_fact(split))
      end

      private

      def build_fact(split)
        combination = split.payment_combination
        transaction = combination&.commerce_transaction
        base = base_attributes(split, combination)

        if combination.nil? || transaction.nil? || split.captured_amount.to_d <= 0
          return unresolved_fact(base, split, combination)
        end

        PallasTrade::FinancialFact.new(
          **base.merge(
            status: PallasTrade::FinancialFact::CONFIRMED,
            fact_type: PallasTrade::FinancialFact::ORDER_ALLOCATION,
            amount: split.captured_amount.to_d,
            currency: split.currency.to_s.presence,
            commerce_transaction_id: transaction.prefixed_id,
            evidence: [:combination_payment_allocated_to_order]
          )
        )
      end

      # 不可 post（不猜）：ORDER_ALLOCATION 语义保留在 fact_type，status=AMBIGUOUS + reason_code 区分，
      # commerce_transaction_id 留空 → Post.postable? 拒绝（FR-4P4-08）。
      def unresolved_fact(base, split, combination)
        reason = if combination.nil?
                   'split_without_combination'
                 elsif split.captured_amount.to_d <= 0
                   'split_not_captured'
                 else
                   'combination_without_commerce_transaction'
                 end

        PallasTrade::FinancialFact.new(
          **base.merge(
            status: PallasTrade::FinancialFact::AMBIGUOUS,
            fact_type: PallasTrade::FinancialFact::ORDER_ALLOCATION,
            amount: nil,
            currency: split.currency.to_s.presence,
            reason_code: reason,
            evidence: [:allocation_not_provable]
          )
        )
      end

      def base_attributes(split, combination)
        {
          fact_type: PallasTrade::FinancialFact::ORDER_ALLOCATION,
          status: nil, amount: nil, currency: split.currency.to_s.presence,
          instrument_class: nil,
          commerce_transaction_id: nil,
          order_id: split.order&.prefixed_id,
          payment_id: split.payment&.prefixed_id,
          refund_id: nil,
          payment_session_id: nil,
          payment_combination_id: combination&.prefixed_id,
          payment_split_id: split.prefixed_id,
          provider: nil,
          provider_payment_reference: nil,
          provider_refund_reference: nil,
          effective_at: deterministic_effective_at(combination),
          evidence: [], reason_code: nil
        }
      end

      # 确定性审计时刻（FR-4P4-02/05）：优先 combination.completed_at（succeed 落账时刻）；
      # 缺省 Time.current。幂等 key 由 PostAllocation 显式稳定构造（不依赖 effective_at），
      # 故此值不影响重放安全，仅用于审计语义。
      def deterministic_effective_at(combination)
        combination&.completed_at || Time.current
      end
    end
  end
end
