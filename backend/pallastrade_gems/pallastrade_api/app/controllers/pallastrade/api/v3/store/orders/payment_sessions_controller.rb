# PALLAS-CUSTOM: Delegate payment-session create/reuse to the Core idempotent start service.
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
              payment_method = current_store.payment_methods.find_by_prefix_id!(permitted_params[:payment_method_id])
              # CHK-P1-5: 可选 expected_version/expected_price_version —— 客户端所见 quote
              # 期望值；服务端不匹配 → checkout_version_conflict（409 + compact latest）。
              result = PallasTrade::PaymentSessions::Start.call(
                order: @order,
                payment_method: payment_method,
                external_data: permitted_params[:external_data] || {},
                expected_version: permitted_params[:expected_version],
                expected_price_version: permitted_params[:expected_price_version]
              )

              if result.success?
                @payment_session = result.value
                render json: serialize_resource(@payment_session), status: :created
              else
                # CHK-P1-3: 传 ResultError 本体（render_service_error 解包）——
                # String/AR errors 渲染与之前一致；{code:,message:,missing_requirements:}
                # 结构化错误（如 checkout_not_ready）渲染 code+details。
                render_service_error(
                  result.error.presence || 'Could not start payment session',
                  code: ERROR_CODES[:validation_error]
                )
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

                # P5 (2026-08-27): 组合支付会话完成 → 统一组合完成。
                # TXN-P2 (2026-09-05): 收敛到 Transaction Payment Handler——txn 化组合
                # （session.commerce_transaction 存在）走 confirm_payment! + Finalize（组合分支
                # 自含入账 Settlement+成员完成）；legacy 无 txn 组合仍走 Complete 适配器。
                if @payment_session.payment_combination.present?
                  PallasTrade::Transactions::OnPaymentSuccess.call(payment_session: @payment_session.reload)
                  render json: serialize_resource(@payment_session.reload)
                  return
                end

                @payment_session.payment_method.complete_payment_session(
                  payment_session: @payment_session,
                  params: complete_params
                )

                if @payment_session.errors.empty?
                  # PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe):
                  # 前端 active complete 后必须驱动订单完成——否则 webhook
                  # handle_success 对已 completed 的会话提前返回，订单停留 pending。
                  # TXN-P2-5 (PRD-20260904-payments-txn-p2-5): 完成收口到
                  # Transaction Payment Handler——带 commerce_transaction 会话走
                  # confirm_payment! + Transactions::Finalize；legacy 无 txn 走原
                  # Carts::Complete（幂等，与 webhook 兜底不冲突）。
                  PallasTrade::Transactions::OnPaymentSuccess.call(payment_session: @payment_session.reload)
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
              params.permit(*(PallasTrade::PermittedAttributes.payment_session_attributes +
                              [:expected_version, :expected_price_version]))
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
