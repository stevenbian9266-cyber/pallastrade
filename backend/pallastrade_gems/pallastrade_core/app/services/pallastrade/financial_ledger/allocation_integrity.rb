# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-4 (PRD-20260906-payments-fin-p4-4)
#
# FinancialLedger::AllocationIntegrity —— 只读 split/allocation sum invariant 校验（FR-4P4-08）。
#
# P4 §23/AC-4014：Σ active ORDER_ALLOCATION == Σ PaymentSplit.captured_amount（per combination）。
# - allocation_total：该组合 splits 关联的 **active（state=posted）** ORDER_ALLOCATION entries 金额和
#   （冲销语义自洽：reversal entry 本身 active 且 amount 相反、原 entry → reversed 被排除 → Σ active 正确）。
# - split_captured_total：Σ split.captured_amount（allocation source of truth，P4 §21）。
# - balanced? = 二者相等。
#
# 只读边界：不创建/更新/删除任何记录；供 spec 断言（AC-4P4-02/04/07）与 P4-7 reconciliation 复用。
module PallasTrade
  module FinancialLedger
    class AllocationIntegrity
      prepend PallasTrade::ServiceModule::Base

      # @param combination [PallasTrade::PaymentCombination]
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ allocation_total:, split_captured_total:, balanced?:, entry_count: }) / failure
      def call(combination:)
        return failure(nil, 'Payment combination not found') if combination.nil?

        splits = combination.payment_splits.reload.to_a
        split_ids = splits.map(&:id)
        split_captured_total = splits.sum { |s| s.captured_amount.to_d }

        allocation_entries = if split_ids.empty?
                               PallasTrade::FinancialLedgerEntry.none
                             else
                               PallasTrade::FinancialLedgerEntry.active
                                                                .where(entry_type: 'ORDER_ALLOCATION')
                                                                .where(payment_split_id: split_ids)
                             end
        allocation_total = allocation_entries.sum(:amount).to_d

        success(
          allocation_total: allocation_total,
          split_captured_total: split_captured_total,
          balanced?: allocation_total == split_captured_total,
          entry_count: allocation_entries.count
        )
      end
    end
  end
end
