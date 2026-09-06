# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-3 (PRD-20260906-payments-fin-p4-3)
#
# FinancialLedger::PostRefund —— Refund posting 编排（FR-4P3-02/03/08）。
#
# 流程：ResolveRefund（FIN-P4-1 只读语义层）→ 门禁（FinancialLedger::Post.postable?）
#   → FinancialLedger::Post（FIN-P4-2 幂等原语）。
#
# 语义（P4 §16/§59：Refund 创建=perform! 成功；posting 失败不影响 Refund Fact）：
#   - REFUND_SUCCEEDED CONFIRMED + 可解析 txn → Post → success({ entry:, fact:, skipped: false })
#   - 不可 post（transaction_id 缺失→AMBIGUOUS / 无 txn）→ success({ entry: nil, fact:, skipped: true, reason: })
#   - 输入缺失 / ResolveRefund failure / Post 硬失败 → failure（subscriber rescue 记录）
#
# 只读边界（FR-4P3-09）：不创建/更新 Refund/Payment/Transaction；唯一写 = FinancialLedgerEntry。
# multiple/partial refunds 各自独立 Post（FR-4P1-28：每次分别解析，不聚合）。
module PallasTrade
  module FinancialLedger
    class PostRefund
      prepend PallasTrade::ServiceModule::Base

      # @param refund [PallasTrade::Refund]
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ entry: FinancialLedgerEntry|nil, fact: FinancialFact, skipped: Boolean, reason: String|nil })
      #   / failure(refund, message)
      def call(refund:)
        return failure(nil, 'Refund not found') if refund.nil?

        resolution = PallasTrade::FinancialFacts::ResolveRefund.call(refund: refund)
        return failure(refund, resolution.error) unless resolution.success?

        fact = resolution.value
        return success({ entry: nil, fact: fact, skipped: true, reason: skip_reason(fact) }) unless PallasTrade::FinancialLedger::Post.postable?(fact)

        posting = PallasTrade::FinancialLedger::Post.call(financial_fact: fact)
        return failure(fact, posting.error) unless posting.success?

        success({ entry: posting.value, fact: fact, skipped: false, reason: nil })
      end

      private

      def skip_reason(fact)
        return 'fact_status_not_confirmed' unless fact.confirmed?
        return 'entry_type_not_activated' unless PallasTrade::FinancialLedgerEntry::ENTRY_TYPES.include?(fact.fact_type)
        return 'commerce_transaction_missing' if fact.commerce_transaction_id.blank?
        return 'amount_or_currency_missing' if fact.amount.blank? || fact.currency.blank?

        'not_postable'
      end
    end
  end
end
