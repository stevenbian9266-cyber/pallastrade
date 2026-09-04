# frozen_string_literal: true

# TXN-P2-2 (PRD-20260904-api-txn-p2-2): 交易 Resume 读模型（owner 作用域）。
module PallasTrade
  module Api
    module V3
      module Store
        class TransactionsController < Store::BaseController
          prepend_before_action :require_authentication!

          # GET /api/v3/store/transactions/:id
          def show
            tx = PallasTrade::CommerceTransaction.
                 where(store_id: current_store.id, customer_id: current_user.id).
                 find_by_prefix_id!(params[:id])
            result = PallasTrade::Transactions::Resume.call(transaction: tx)
            render json: { data: resume_payload(result.value) }
          rescue ActiveRecord::RecordNotFound
            render json: {
              error: { code: 'record_not_found', message: 'Transaction not found' }
            }, status: :not_found
          end

          private

          def resume_payload(payload)
            {
              id: payload[:transaction].prefixed_id,
              type: 'transaction',
              state: payload[:state],
              purpose: payload[:purpose],
              currency: payload[:currency],
              amount: payload[:amount].to_s,
              snapshot_fingerprint: payload[:snapshot_fingerprint],
              participants: payload[:participants],
              payment_sessions: payload[:payment_sessions],
              recovery: payload[:recovery],
              completion: payload[:completion]
            }
          end
        end
      end
    end
  end
end
