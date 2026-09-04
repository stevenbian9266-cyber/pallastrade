# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-4 (PRD-20260904-payments-txn-p2-4)
# Recovery 驱动 Job：对 recovery_required/finalizing 交易执行
# Transactions::Recover（先 PaymentFactResolver 权威判定，再分支行动）。
# 失败已由 Recover 记录到 transaction（recovery_attempts/last_error_*），
# 本 Job 不盲重抛——finalize/守卫类失败交上层调度/人工（参考
# CombinationSettleJob 语义：资金已入账的订单保留供人工介入，不无限重试）。
module PallasTrade
  module Transactions
    class RecoverJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.payment_webhooks

      retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
      retry_on ActiveRecord::LockWaitTimeout, wait: 5.seconds, attempts: 3
      discard_on ActiveRecord::RecordNotFound

      def perform(transaction_prefixed_id)
        transaction = PallasTrade::CommerceTransaction.find_by_prefix_id!(transaction_prefixed_id)
        result = PallasTrade::Transactions::Recover.call(transaction: transaction)
        return if result.success?

        Rails.logger.warn(
          "[TXN-P2-4] Recover #{transaction.prefixed_id} incomplete: #{result.error}"
        )
      end
    end
  end
end
