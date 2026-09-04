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
          end
        end
      end
    end
  end
end
