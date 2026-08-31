# PALLAS-CUSTOM: Keep customer order history explicitly scoped by store and JWT user ID.
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
              current_store.orders
                           .where(user_id: current_user.id)
                           .complete
                           .preload_associations_lazily
            end
          end
        end
      end
    end
  end
end
