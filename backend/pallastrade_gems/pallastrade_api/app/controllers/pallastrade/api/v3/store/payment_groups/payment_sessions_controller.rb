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
