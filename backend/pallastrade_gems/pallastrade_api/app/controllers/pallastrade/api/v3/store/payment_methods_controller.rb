# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
#
# Store API — front-facing payment methods for the combined payment page.
#
#   GET /api/v3/store/payment_methods
module PallasTrade
  module Api
    module V3
      module Store
        class PaymentMethodsController < Store::BaseController
          # GET /api/v3/store/payment_methods
          def index
            methods = current_store.payment_methods.active.available_on_front_end
            render json: {
              data: methods.map { |pm| serializer_class.new(pm, params: serializer_params).to_h },
              meta: { count: methods.size }
            }
          end

          protected

          def serializer_class
            PallasTrade.api.payment_method_serializer
          end
        end
      end
    end
  end
end
