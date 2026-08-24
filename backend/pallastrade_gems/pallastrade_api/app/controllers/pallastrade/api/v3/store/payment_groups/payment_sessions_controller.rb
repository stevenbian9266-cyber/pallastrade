# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
#
# Store API — payment sessions scoped to a payment group. One session covers
# every member order; a successful completion (redirect-back or webhook)
# completes all of them.
#
#   POST  /api/v3/store/payment_groups/:payment_group_id/payment_sessions
#   GET   /api/v3/store/payment_groups/:payment_group_id/payment_sessions/:id
#   PATCH /api/v3/store/payment_groups/:payment_group_id/payment_sessions/:id
#   PATCH /api/v3/store/payment_groups/:payment_group_id/payment_sessions/:id/complete
module PallasTrade
  module Api
    module V3
      module Store
        module PaymentGroups
          class PaymentSessionsController < Store::BaseController
            include PallasTrade::Api::V3::JwtAuthentication

            prepend_before_action :require_authentication!
            before_action :set_payment_group!
            before_action :set_payment_session, only: [:show, :update, :complete]
            # PALLAS-CUSTOM: 下单前置校验（PRD-20260824）— 登录/黑名单/风控，服务端强制执行
            before_action :enforce_checkout_guard, only: [:create]

            # POST /api/v3/store/payment_groups/:payment_group_id/payment_sessions
            def create
              payment_method = current_store.payment_methods.find_by_prefix_id!(permitted_params[:payment_method_id])

              @payment_session = payment_method.create_payment_session(
                order: @payment_group.primary_order,
                payment_group: @payment_group,
                amount: permitted_params[:amount],
                external_data: permitted_params[:external_data] || {}
              )

              if @payment_session.persisted?
                render json: serialize_resource(@payment_session), status: :created
              else
                render_errors(@payment_session.errors)
              end
            end

            # GET /api/v3/store/payment_groups/:payment_group_id/payment_sessions/:id
            def show
              render json: serialize_resource(@payment_session)
            end

            # PATCH /api/v3/store/payment_groups/:payment_group_id/payment_sessions/:id
            def update
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

            # PATCH /api/v3/store/payment_groups/:payment_group_id/payment_sessions/:id/complete
            def complete
              @payment_session.reload

              if @payment_session.completed?
                render json: serialize_resource(@payment_session)
                return
              end

              @payment_session.payment_method.complete_payment_session(
                payment_session: @payment_session,
                params: complete_params
              )

              if @payment_session.errors.empty?
                # PALLAS-CUSTOM: 合并支付 — complete 成功后立即完成组内全部订单。
                # 幂等（PaymentGroups::Complete 跳过已支付/已完成订单），
                # 让前端在 storefront 主动 complete 时立即看到完成，不依赖 webhook 时序。
                if @payment_session.payment_group.present?
                  begin
                    PallasTrade::PaymentGroups::Complete.call(
                      payment_group: @payment_session.payment_group,
                      payment_session: @payment_session
                    )
                  rescue StandardError => e
                    Rails.error.report(
                      e,
                      context: {
                        payment_group_id: @payment_session.payment_group.id,
                        payment_session_id: @payment_session.id
                      },
                      source: 'PallasTrade.api.payment_group.complete'
                    )
                  end
                end
                render json: serialize_resource(@payment_session.reload)
              else
                render_errors(@payment_session.errors)
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

            # PALLAS-CUSTOM: 下单前置校验（PRD-20260824）— 服务端强制执行
            # 未登录/黑名单/风控命中 → 403 + { error: { code, message } }（FR-004）
            def enforce_checkout_guard
              result = PallasTrade::Checkout::Guard.call(user: current_user)
              return if result.success?

              error = result.error.value
              render json: {
                error: {
                  code: error[:code],
                  message: error[:message]
                }
              }, status: :forbidden
            end

            def set_payment_group!
              @payment_group = PallasTrade::PaymentGroup
                               .where(store: current_store, customer: current_user)
                               .find_by_prefix_id!(params[:payment_group_id])
            end

            def set_payment_session
              @payment_session = @payment_group.payment_sessions.find_by_prefix_id(params[:id]) ||
                                 @payment_group.payment_sessions.find_by!(external_id: params[:id])
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
