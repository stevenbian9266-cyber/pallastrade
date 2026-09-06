# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-3 (PRD-20260906-payments-fin-p4-3)
#
# FinancialLedger::PostPayment —— Payment posting 编排（FR-4P3-01/03/08）。
#
# 流程：ResolvePayment（FIN-P4-1 只读语义层）→ 门禁（FinancialLedger::Post.postable?）
#   → FinancialLedger::Post（FIN-P4-2 幂等原语）。
#
# 语义（P4 §16/§57/§65：Journal 失败不逆转 Payment Fact，不创建新 Payment）：
#   - fact 可 post（CONFIRMED + 激活 entry_type + 可解析 txn）→ Post → success({ entry:, fact:, skipped: false })
#   - fact 不可 post（AMBIGUOUS/UNSUPPORTED/AUTHORIZED_ONLY/UNPAID/NONE/无 txn）→
#     success({ entry: nil, fact:, skipped: true, reason: }) —— 业务正常结局（不猜、不部分记录，FIN-INV-09）
#   - 输入缺失 / ResolvePayment failure / Post 硬失败 → failure（subscriber rescue 记录，不阻断资金流）
#
# 只读边界（FR-4P3-09）：本服务不创建/更新/删除 Payment/PaymentSession/CommerceTransaction/Order，
# 不改任何 state machine；唯一写 = FinancialLedgerEntry（经 Post）。
module PallasTrade
  module FinancialLedger
    class PostPayment
      prepend PallasTrade::ServiceModule::Base

      # @param payment [PallasTrade::Payment]
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ entry: FinancialLedgerEntry|nil, fact: FinancialFact, skipped: Boolean, reason: String|nil })
      #   / failure(payment, message)
      def call(payment:)
        return failure(nil, 'Payment not found') if payment.nil?

        resolution = PallasTrade::FinancialFacts::ResolvePayment.call(payment: payment)
        return failure(payment, resolution.error) unless resolution.success?

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
