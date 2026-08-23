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

            def set_parent
              @parent = current_user
            end

            def parent_association
              :orders
            end

            # PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
            # ?scope=unpaid → placed-but-unpaid orders (for combined payment picker)
            def scope
              base = super.for_store(current_store)
              return base.unpaid_for_combined_payment if params[:scope] == 'unpaid'

              base.complete
            end
          end
        end
      end
    end
  end
end
