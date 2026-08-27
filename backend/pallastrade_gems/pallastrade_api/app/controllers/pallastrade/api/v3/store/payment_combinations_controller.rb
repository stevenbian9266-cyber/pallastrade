module PallasTrade
  module Api
    module V3
      module Store
        # Store API — 合并支付组合（P5, 2026-08-27，flag 灰度）
        # POST /api/v3/store/payment_combinations
        class PaymentCombinationsController < Store::BaseController
          prepend_before_action :require_authentication!

          # POST /api/v3/store/payment_combinations
          # body: { order_ids: ["order_...", ...], payment_method_id: "pm_..." }
          def create
            orders = resolve_orders(permitted_params[:order_ids])
            payment_method = current_store.payment_methods.find_by_prefix_id!(permitted_params[:payment_method_id])

            result = PallasTrade::Payments::PaymentCombinations::Create.call(
              store: current_store,
              customer: current_user,
              orders: orders,
              payment_method: payment_method
            )

            if result.success?
              render json: serialize_resource(result.value), status: :created
            else
              render_service_error(result.error)
            end
          end

          # GET /api/v3/store/payment_combinations/:id
          def show
            combination = PallasTrade::PaymentCombination
                          .where(customer_id: current_user.id, store_id: current_store.id)
                          .find_by_prefix_id!(params[:id])
            render json: serialize_resource(combination)
          end

          protected

          def serializer_class
            PallasTrade.api.payment_combination_serializer
          end

          def permitted_params
            params.permit(:payment_method_id, { order_ids: [] })
          end

          private

          # 解析 prefixed 订单 id → 当前用户 + 当前 store 的订单
          def resolve_orders(ids)
            numeric_ids = Array(ids).filter_map do |prefixed|
              PallasTrade::PrefixedId.decode_prefixed_id(prefixed) if prefixed.is_a?(String)
            end
            current_user.orders.for_store(current_store).where(id: numeric_ids)
          end

          def serialize_resource(resource)
            serializer_class.new(resource, params: serializer_params).to_h
          end
        end
      end
    end
  end
end
