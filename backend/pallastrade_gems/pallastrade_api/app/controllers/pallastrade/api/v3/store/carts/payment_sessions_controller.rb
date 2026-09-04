module PallasTrade
  module Api
    module V3
      module Store
        module Carts
          # ── P0-7 (FR-070/FR-071): LEGACY / COMPATIBILITY ONLY ───────────────────
          # Order 域 PaymentSession Flow = Canonical Standard（orders/payment_sessions
          # + PaymentSessions::Start）；本控制器（Cart 域 legacy）= Compatibility Only。
          # 入口已打 structured usage log（payment.legacy_flow.used），用于统计真实流量。
          #
          # ⛔ DO NOT ADD NEW PAYMENT FEATURES TO LEGACY FLOW
          # 新支付能力一律走 Order 域 Start；Legacy 只做存量兼容，不删。
          class PaymentSessionsController < Store::BaseController
            include PallasTrade::Api::V3::CartResolvable
            include PallasTrade::Api::V3::OrderLock

            before_action :find_cart!
            before_action :set_payment_session, only: [:show, :update, :complete]

            # POST /api/v3/store/carts/:cart_id/payment_sessions
            # P0-3 (PRD FR-031/FR-032): cart/Express 会话创建委托 Standard
            # PaymentSessions::Start——继承 order lock 作用域 + active 会话复用 +
            # 稳定 operation_key（provider idempotency），消除连续点击/并发/
            # HTTP retry/provider timeout 后重试造成的重复有效 PSP payment。
            # （Start 自身负责锁生命周期；此处不再套 with_order_lock 以免持锁等 provider。）
            def create
              payment_method = current_store.payment_methods.find_by_prefix_id!(permitted_params[:payment_method_id])

              # P0-7: Legacy usage metric（每次调用计数，供统计 Legacy 真实流量）。
              log_legacy_flow_usage(payment_method)

              result = PallasTrade::PaymentSessions::Start.call(
                order: @cart,
                payment_method: payment_method,
                external_data: permitted_params[:external_data] || {}
              )

              if result.success?
                @payment_session = result.value
                render json: serialize_resource(@payment_session), status: :created
              else
                render_service_error(
                  result.error.to_s.presence || 'Could not start payment session',
                  code: ERROR_CODES[:validation_error]
                )
              end
            end

            # GET /api/v3/store/carts/:cart_id/payment_sessions/:id
            def show
              render json: serialize_resource(@payment_session)
            end

            # PATCH /api/v3/store/carts/:cart_id/payment_sessions/:id
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

            # PATCH /api/v3/store/carts/:cart_id/payment_sessions/:id/complete
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

            # P0-7 (FR-071): Legacy usage metric —— 固定 key `payment.legacy_flow.used`
            # 供日志管道按 message 计数（flow_type / entry_point / method / order）。
            # entry_point 由 external_data 启发式推断（服务端无法区分时归 unknown）。
            def log_legacy_flow_usage(payment_method)
              ext = permitted_params[:external_data] || {}
              ext = ext.to_h if ext.respond_to?(:to_h) && !ext.is_a?(Hash)
              ext = ext.with_indifferent_access if ext.respond_to?(:with_indifferent_access)

              entry_point =
                if ext[:return_url].present?
                  'legacy_one_page'
                elsif ext[:stripe_payment_method_id].present?
                  'express_checkout'
                else
                  'unknown'
                end

              Rails.logger.info(
                message: 'payment.legacy_flow.used',
                flow_type: 'legacy_cart_session_create',
                entry_point: entry_point,
                payment_method_id: payment_method.prefixed_id,
                order_id: @cart.prefixed_id
              )
            end

            def set_payment_session
              @payment_session = @cart.payment_sessions.find_by_prefix_id(params[:id]) ||
                @cart.payment_sessions.find_by!(external_id: params[:id])
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
