module PallasTrade
  module Api
    module V3
      module Store
        # Store API — 合并支付组合（P5, 2026-08-27，flag 灰度）
        # POST /api/v3/store/payment_combinations
        class PaymentCombinationsController < Store::BaseController
          prepend_before_action :require_authentication!

          # POST /api/v3/store/payment_combinations
          # body: { order_ids: ["order_...", ...], payment_method_id?: "pm_..." }
          # PALLAS-CUSTOM (2026-08-29, bugfix): payment_method_id 可选——缺省时服务端选
          # 第一个可用会话类支付方式（如 Stripe），避免前端依赖购物车里的支付方式。
          def create
            orders = resolve_orders(permitted_params[:order_ids])
            payment_method = resolve_payment_method(permitted_params[:payment_method_id])
            return if payment_method.nil? # resolve_payment_method 已渲染错误

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

          # PALLAS-CUSTOM (2026-08-29, bugfix): payment_method_id 可选；缺省选 store
          # 第一个可用会话类支付方式（session_required，如 Stripe），否则第一个 active。
          # 用直接查询（绕过 Store#payment_methods 关联 scope）保证能找到支付方式。
          # 无可用支付方式时渲染 422 并返回 nil（create 据此提前返回）。
          def resolve_payment_method(id)
            payment_method =
              if id.present?
                current_store.payment_methods.find_by_prefix_id!(id)
              else
                scope = PallasTrade::PaymentMethod
                        .where(store_id: current_store.id)
                        .order(position: :asc)
                scope.to_a.find(&:session_required?) ||
                  scope.to_a.find(&:active?) ||
                  scope.first
              end

            if payment_method.nil?
              render json: {
                error: {
                  code: 'payment_method_not_found',
                  message: 'No payment method available'
                }
              }, status: :unprocessable_entity
              return nil
            end

            payment_method
          end

          def serialize_resource(resource)
            serializer_class.new(resource, params: serializer_params).to_h
          end
        end
      end
    end
  end
end
