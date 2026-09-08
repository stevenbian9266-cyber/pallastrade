# PALLAS-CUSTOM: Keep submitted and completed customer orders scoped by store and JWT user ID.
module PallasTrade
  module Api
    module V3
      module Store
        module Customer
          class OrdersController < ResourceController
            prepend_before_action :require_authentication!

            protected

            def model_class
              PallasTrade::Order
            end

            def serializer_class
              PallasTrade.api.order_serializer
            end

            def scope
              owned_orders = current_store.orders.where(user_id: current_user.id)
              owned_orders.where.not(submitted_at: nil)
                          .or(owned_orders.complete)
                          .preload_associations_lazily
            end

            # PALLAS-CUSTOM: 订单历史默认按创建时间由近到远排序（PRD-20260908-checkout-商城前台-order）。
            # 复用框架 apply_collection_sort 扩展点：客户端显式 sort（q[s]/sort 参数）仍优先，
            # 此处 order 仅作「无显式 sort」时的确定性兜底；同秒创建以 id desc 稳定排序。
            def apply_collection_sort(collection)
              collection.order(created_at: :desc, id: :desc)
            end
          end
        end
      end
    end
  end
end
