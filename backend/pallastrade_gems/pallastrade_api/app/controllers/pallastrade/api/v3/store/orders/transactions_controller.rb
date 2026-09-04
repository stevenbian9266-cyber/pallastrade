# frozen_string_literal: true

# TXN-P2-2 (PRD-20260904-api-txn-p2-2): 单订单 durable CommerceTransaction 启动入口。
# 委托 PallasTrade::Transactions::Start（quote 同意/幂等/snapshot/PaymentSessions::Start）。
module PallasTrade
  module Api
    module V3
      module Store
        module Orders
          class TransactionsController < Store::BaseController
            include PallasTrade::Api::V3::OrderResolvable

            before_action :find_order

            # POST /api/v3/store/orders/:order_id/transactions
            def create
              payment_method = current_store.payment_methods.find_by_prefix_id!(permitted_params[:payment_method_id])
              result = PallasTrade::Transactions::Start.call(
                order: @order,
                payment_method: payment_method,
                purpose: permitted_params[:purpose].presence || 'purchase',
                external_data: permitted_params[:external_data] || {},
                expected: {
                  checkout_version: permitted_params[:expected_checkout_version],
                  price_version: permitted_params[:expected_price_version]
                }.compact
              )

              if result.success?
                render json: { data: transaction_payload(result.value[:transaction], result.value[:payment_session]) },
                       status: :created
              else
                render_service_error(result.error)
              end
            end

            private

            def permitted_params
              params.permit(
                :payment_method_id, :purpose,
                :expected_checkout_version, :expected_price_version,
                external_data: {}
              )
            end

            def transaction_payload(transaction, session)
              {
                id: transaction.prefixed_id,
                type: 'transaction',
                attributes: {
                  state: transaction.state,
                  purpose: transaction.purpose,
                  currency: transaction.currency,
                  amount: transaction.amount.to_s,
                  checkout_version: transaction.checkout_version,
                  price_version: transaction.price_version,
                  snapshot_fingerprint: transaction.snapshot_fingerprint,
                  completed_at: transaction.completed_at&.iso8601
                },
                payment_execution: session_payload(session)
              }
            end

            def session_payload(session)
              return nil if session.nil?

              {
                id: session.prefixed_id,
                type: 'payment_session',
                status: session.status,
                amount: session.amount.to_s,
                currency: session.currency,
                external_data: session.external_data
              }
            end
          end
        end
      end
    end
  end
end
