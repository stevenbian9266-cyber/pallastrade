# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-2 (PRD-20260904-api-txn-p2-2)
#
# Transactions::Resume —— 只读交易聚合（读模型），供 GET /transactions/:id。
# 返回 transaction + participants(orders) + payment sessions + payment/完成摘要
# + recovery 摘要；不改变任何状态（零副作用）。
module PallasTrade
  module Transactions
    class Resume
      prepend PallasTrade::ServiceModule::Base

      # @param transaction [PallasTrade::CommerceTransaction]
      def call(transaction:)
        return failure(nil, 'Transaction not found') if transaction.nil?

        participants = transaction.transaction_orders.includes(:order).order(:id).map do |torder|
          order = torder.order
          {
            order_id: order&.prefixed_id,
            role: torder.role,
            amount_snapshot: torder.amount_snapshot,
            completion_status: torder.completion_status,
            completed: order.present? && order.completed?
          }
        end

        sessions = transaction.payment_sessions.order(:id).map do |session|
          {
            id: session.prefixed_id,
            status: session.status,
            amount: session.amount,
            currency: session.currency,
            external_id: session.external_id,
            completed: session.completed?
          }
        end

        payload = {
          transaction: transaction,
          participants: participants,
          payment_sessions: sessions,
          state: transaction.state,
          purpose: transaction.purpose,
          amount: transaction.amount,
          currency: transaction.currency,
          snapshot_fingerprint: transaction.snapshot_fingerprint,
          recovery: {
            attempts: transaction.recovery_attempts,
            last_error_code: transaction.last_error_code,
            last_error_class: transaction.last_error_class,
            last_error_message: transaction.last_error_message
          },
          completion: {
            completed_at: transaction.completed_at&.iso8601,
            participants_completed: participants.count { |p| p[:completed] },
            participants_total: participants.size
          }
        }

        success(payload)
      end
    end
  end
end
