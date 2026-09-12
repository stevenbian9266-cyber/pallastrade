# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-3 (PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile)
#
# FinancialLedger::PostDispute —— Dispute posting 编排（FR-P73-06/07；与 PostRefund 同构）。
#
# 流程：ResolveDispute（只读事实层）→ 门禁（Post.postable? + effective_at 稳定性）→
#   FinancialLedger::Post（FIN-P4-2 幂等原语）。
#
# 语义（P4 §16）：posting 失败不影响 Dispute 事实；subscriber async + 幂等键 → 重试不重复入账。
#   - 现金事实 CONFIRMED + 可解析 txn + funds 时间戳 → Post → success({ entry:, fact:, skipped: false })
#   - 不可 post（非现金类型 / 未证实 / 无 txn / 金额币种或时间戳缺失）→
#     success({ entry: nil, fact:, skipped: true, reason: <封闭枚举> })
#   - 输入缺失 / ResolveDispute failure / Post 硬失败 → failure（subscriber rescue 记录）
#
# 只读边界（FR-P73-12）：不创建/更新 Dispute/Payment/Transaction；唯一写 = FinancialLedgerEntry。
module PallasTrade
  module FinancialLedger
    class PostDispute
      prepend PallasTrade::ServiceModule::Base

      # @param dispute [PallasTrade::Dispute]
      # @param fact_type [String, nil] 事件作用域事实类型提示（见 `ResolveDispute`：终态 won/lost 不会吞掉
      #   后续 funds 事件；缺省 = P7-2 最强事实）
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ entry: FinancialLedgerEntry|nil, fact: FinancialFact, skipped: Boolean, reason: String|nil })
      #   / failure(fact|dispute, message)
      def call(dispute:, fact_type: nil)
        return failure(nil, 'Dispute not found') if dispute.nil?

        resolution = PallasTrade::FinancialFacts::ResolveDispute.call(dispute: dispute, fact_type: fact_type)
        return failure(dispute, resolution.error) unless resolution.success?

        fact = resolution.value
        reason = self.class.skip_reason_for(fact)
        return success({ entry: nil, fact: fact, skipped: true, reason: reason }) if reason

        posting = PallasTrade::FinancialLedger::Post.call(financial_fact: fact)
        return failure(fact, posting.error) unless posting.success?

        success({ entry: posting.value, fact: fact, skipped: false, reason: nil })
      end

      # 封闭 skip reason 枚举（FR-P73-07；与 PostRefund 对齐并追加 effective_at_missing）。
      # `nil` = 可 post。`ReconcileDispute` 复用同一判定，保证「入账」与「对账」口径一致。
      #
      # @return [String, nil]
      def self.skip_reason_for(fact)
        return 'fact_not_found' if fact.nil?
        return 'fact_status_not_confirmed' unless fact.confirmed?
        activated = PallasTrade::FinancialLedgerEntry::ENTRY_TYPES.include?(fact.fact_type)
        return 'entry_type_not_activated' unless activated

        return 'commerce_transaction_missing' if fact.commerce_transaction_id.blank?
        return 'amount_or_currency_missing' if fact.amount.blank? || fact.currency.blank?
        # 无资金时间戳 → 幂等键无法稳定派生（Post 会 fallback Time.current → 重复 posting），一律不猜
        return 'effective_at_missing' if fact.effective_at.blank?
        return 'not_postable' unless PallasTrade::FinancialLedger::Post.postable?(fact)

        nil
      end
    end
  end
end
