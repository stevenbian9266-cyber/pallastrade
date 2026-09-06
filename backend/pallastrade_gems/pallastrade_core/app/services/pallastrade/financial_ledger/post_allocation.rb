# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-4 (PRD-20260906-payments-fin-p4-4)
#
# FinancialLedger::PostAllocation —— 单个 PaymentSplit 的 ORDER_ALLOCATION posting 编排（FR-4P4-05）。
#
# 流程：ResolveAllocation（只读）→ 门禁（FinancialLedger::Post.postable?）→ Post（幂等原语）。
#
# 幂等（FR-4P4-05）：显式稳定 key `fact:ORDER_ALLOCATION:<txn_id>:<split_id>`——不依赖 effective_at 时刻，
# 事件重放 / job retry / recovery 换时刻不会产生重复 entry（Post 支持显式 idempotency_key）。
#
# 语义（P4 §22/§23 + FIN-INV-05/09）：ORDER_ALLOCATION 非 cash inflow（AC-4013），
# 只是资金归属投影；不可 post（AMBIGUOUS：无组合/无 txn/captured=0）→ success({ skipped: true }) 不猜。
# 只读边界（FR-4P4-09）：唯一写 = FinancialLedgerEntry（经 Post），不碰 split/combination/order。
module PallasTrade
  module FinancialLedger
    class PostAllocation
      prepend PallasTrade::ServiceModule::Base

      # @param split [PallasTrade::PaymentSplit]
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ entry: FinancialLedgerEntry|nil, fact: FinancialFact, skipped: Boolean, reason: String|nil })
      #   / failure(split, message)
      def call(split:)
        return failure(nil, 'Payment split not found') if split.nil?

        resolution = PallasTrade::FinancialFacts::ResolveAllocation.call(split: split)
        return failure(split, resolution.error) unless resolution.success?

        fact = resolution.value
        unless PallasTrade::FinancialLedger::Post.postable?(fact)
          return success({ entry: nil, fact: fact, skipped: true, reason: skip_reason(fact) })
        end

        key = allocation_key(fact)
        posting = PallasTrade::FinancialLedger::Post.call(financial_fact: fact, idempotency_key: key)
        return failure(fact, posting.error) unless posting.success?

        success({ entry: posting.value, fact: fact, skipped: false, reason: nil })
      end

      private

      # 显式稳定幂等 key（不依赖 effective_at 时刻——重放/重试安全）。
      def allocation_key(fact)
        "fact:#{fact.fact_type}:#{fact.commerce_transaction_id}:#{fact.payment_split_id}"
      end

      def skip_reason(fact)
        return fact.reason_code if fact.reason_code.present? # 语义化 skip（split_without_combination 等）

        return 'fact_status_not_confirmed' unless fact.confirmed?
        return 'entry_type_not_activated' unless PallasTrade::FinancialLedgerEntry::ENTRY_TYPES.include?(fact.fact_type)
        return 'commerce_transaction_missing' if fact.commerce_transaction_id.blank?
        return 'amount_or_currency_missing' if fact.amount.blank? || fact.currency.blank?

        'not_postable'
      end
    end
  end
end
