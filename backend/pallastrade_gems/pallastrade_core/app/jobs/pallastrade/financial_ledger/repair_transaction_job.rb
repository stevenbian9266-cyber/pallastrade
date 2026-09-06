# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-8 (PRD-20260906-payments-fin-p4-8)
#
# FinancialLedger::RepairTransactionJob —— Journal 幂等补记驱动 Job。
#
# 由 ReconcileSweeperJob（journal-missing 自动 repair，§44 允许）与 rake/manual 触发；
# RepairTransaction 全幂等（Post idempotency key + already_present 检测），重复调度安全。
# 失败不盲重抛：RepairTransaction failure 为逐源 skipped（不中断整批），日志记录供人工/runbook。
module PallasTrade
  module FinancialLedger
    class RepairTransactionJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      discard_on ActiveRecord::RecordNotFound

      def perform(transaction_prefixed_id)
        transaction = PallasTrade::CommerceTransaction.find_by_prefix_id!(transaction_prefixed_id)
        result = PallasTrade::FinancialLedger::RepairTransaction.call(transaction: transaction)
        return if result.success?

        Rails.logger.warn(
          "[FIN-P4-8] RepairTransaction #{transaction.prefixed_id} failed: #{result.error.inspect}"
        )
      end
    end
  end
end
