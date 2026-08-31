module PallasTrade
  module Api
    module V3
      module Store
        module Orders
          # 订单流程标准电商改造 P1（2026-08-30）：订单域支付会话（Checkout 纯支付）。
          # 与 legacy Carts::PaymentSessionsController（挂在购物车/Order 同表）不同——
          # 新流程提交订单后是正式 Order（or_ 前缀），支付会话直接挂订单。
          # 完成路径：complete → payment_method.complete_payment_session → webhook/
          # confirm → PallasTrade::Dependencies.carts_complete_service（Carts::Complete，
          # 标准流程分支 pay! + finalize!）。
          class PaymentSessionsController < Store::BaseController
            include PallasTrade::Api::V3::OrderResolvable
            include PallasTrade::Api::V3::OrderLock

            # PALLAS-CUSTOM: Payment is allowed for an owned completed order that still
            # has a balance due. The generic :update ability intentionally rejects every
            # completed order, so resolve through the ownership-scoped :show permission
            # instead. order_scope still enforces current store + customer/token isolation.
            before_action :find_order
            before_action :set_payment_session, only: [:show, :update, :complete]

            # POST /api/v3/store/orders/:order_id/payment_sessions
            def create
              with_order_lock do
                payment_method = current_store.payment_methods.find_by_prefix_id!(permitted_params[:payment_method_id])

                @payment_session = payment_method.create_payment_session(
                  order: @order,
                  amount: permitted_params[:amount],
                  external_data: permitted_params[:external_data] || {}
                )

                if @payment_session.persisted?
                  render json: serialize_resource(@payment_session), status: :created
                else
                  render_errors(@payment_session.errors)
                end
              end
            end

            # GET /api/v3/store/orders/:order_id/payment_sessions/:id
            def show
              render json: serialize_resource(@payment_session)
            end

            # PATCH /api/v3/store/orders/:order_id/payment_sessions/:id
            def update
              with_order_lock do
                @payment_session.reload

                @payment_session.payment_method.update_payment_session(
                  payment_session: @payment_session,
                  amount: permitted_params[:amount],
                  external_data: permitted_params[:external_data] || {}
                )

                if @payment_session.errors.empty?
                  render json: serialize_resource(@payment_session.reload)
                else
                  render_errors(@payment_session.errors)
                end
              end
            end

            # PATCH /api/v3/store/orders/:order_id/payment_sessions/:id/complete
            def complete
              with_order_lock do
                @payment_session.reload

                if @payment_session.completed?
                  render json: serialize_resource(@payment_session)
                  return
                end

                # P5 (2026-08-27): 组合支付会话完成 → 走 PaymentCombinations::Complete
                # （先入账支付 → 逐个完成所有成员订单），与 Webhook 路径收敛到同一服务。
                if @payment_session.payment_combination.present?
                  PallasTrade::Payments::PaymentCombinations::Complete.call(payment_session: @payment_session)
                  render json: serialize_resource(@payment_session.reload)
                  return
                end

                @payment_session.payment_method.complete_payment_session(
                  payment_session: @payment_session,
                  params: complete_params
                )

                if @payment_session.errors.empty?
                  render json: serialize_resource(@payment_session.reload)
                else
                  render_errors(@payment_session.errors)
                end
              end
            end

            protected

            def serializer_class
              PallasTrade.api.payment_session_serializer
            end

            def permitted_params
              params.permit(PallasTrade::PermittedAttributes.payment_session_attributes)
            end

            def complete_params
              params.permit(:session_result, { external_data: {} })
            end

            private

            def set_payment_session
              @payment_session = @order.payment_sessions.find_by_prefix_id(params[:id]) ||
                                 @order.payment_sessions.find_by!(external_id: params[:id])
            end

            def serialize_resource(resource)
              serializer_class.new(resource, params: serializer_params).to_h
            end
          end
        end
      end
    end
  end
end
