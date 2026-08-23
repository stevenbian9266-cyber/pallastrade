# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
#
# Store API — combined payment groups.
#
#   POST /api/v3/store/payment_groups
#   GET  /api/v3/store/payment_groups/:id
#
# Requires a logged-in customer (JWT). A group is always scoped to
# current_store + current_user; members are validated server-side.
module PallasTrade
  module Api
    module V3
      module Store
        class PaymentGroupsController < Store::BaseController
          include PallasTrade::Api::V3::JwtAuthentication

          prepend_before_action :require_authentication!
          before_action :set_payment_group, only: [:show]

          # POST /api/v3/store/payment_groups
          # body: { order_ids: ["or_xxx", "or_yyy"] }
          def create
            result = PallasTrade::PaymentGroups::Create.call(
              store: current_store,
              order_ids: Array(permitted_params[:order_ids]).compact_blank,
              user: current_user
            )

            if result.success?
              render json: serialize_resource(result.value), status: :created
            else
              render_error(
                code: result.error.value.to_s,
                message: payment_group_error_message(result.error.value),
                status: :unprocessable_entity
              )
            end
          end

          # GET /api/v3/store/payment_groups/:id
          def show
            render json: serialize_resource(@payment_group)
          end

          protected

          def serializer_class
            PallasTrade.api.payment_group_serializer
          end

          def permitted_params
            params.permit(PallasTrade::PermittedAttributes.payment_group_attributes)
          end

          private

          def set_payment_group
            @payment_group = PallasTrade::PaymentGroup
                             .where(store: current_store, customer: current_user)
                             .find_by_prefix_id!(params[:id])
          end

          def serialize_resource(resource)
            serializer_class.new(resource, params: serializer_params).to_h
          end

          def payment_group_error_message(code)
            {
              orders_not_found: 'One or more orders could not be found',
              mixed_currency: 'All orders must use the same currency',
              orders_not_owned: 'All orders must belong to you',
              order_canceled: 'A selected order has been canceled',
              order_already_paid: 'A selected order has already been paid',
              order_in_active_group: 'A selected order is already in an active payment group'
            }[code.to_sym] || code.to_s
          end
        end
      end
    end
  end
end
