module PallasTrade
  module Api
    module V3
      module Store
        module Carts
          class PaymentsController < Store::BaseController
            include PallasTrade::Api::V3::CartResolvable
            include PallasTrade::Api::V3::LegacyFlowObservable

            before_action :find_cart!
            # P0-7 / PRD-20260914-checkout-cart-store-credits-canonical FR-007：legacy 流量观测
            # （订单域支付：canonical 等价能力在 /orders/:id/payment_sessions；是否迁移看流量）。
            before_action :log_legacy_usage_once_payments

            # POST /api/v3/store/carts/:cart_id/payments
            # Creates a payment for non-session payment methods (e.g. Check, Cash on Delivery, Bank Transfer)
            def create
              payment_method = current_store.payment_methods.find_by_prefix_id!(params[:payment_method_id])

              if payment_method.session_required?
                return render_error(
                  code: 'payment_session_required',
                  message: PallasTrade.t('api.v3.payments.session_required'),
                  status: :unprocessable_content
                )
              end

              unless payment_method.available_for_order?(@cart)
                return render_error(
                  code: 'payment_method_unavailable',
                  message: PallasTrade.t('api.v3.payments.method_unavailable'),
                  status: :unprocessable_content
                )
              end

              amount = params[:amount].presence || @cart.total_minus_store_credits

              @payment = @cart.payments.build(
                payment_method: payment_method,
                amount: amount,
                metadata: params[:metadata].present? ? params[:metadata].to_unsafe_h : {}
              )

              if @payment.save
                render json: PallasTrade.api.payment_serializer.new(@payment, params: serializer_params).to_h, status: :created
              else
                render_errors(@payment.errors)
              end
            end

            private

            def log_legacy_usage_once_payments
              log_legacy_usage_once(flow_type: 'legacy_cart_payments', action: action_name)
            end

            # §45 matrix：本行 canonical = Transaction/Payment（订单域会话）。
            def legacy_canonical_successor
              '/api/v3/store/orders/:order_id/payment_sessions'
            end
          end
        end
      end
    end
  end
end
