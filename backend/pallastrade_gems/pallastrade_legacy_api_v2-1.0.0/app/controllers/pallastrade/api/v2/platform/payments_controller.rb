module PallasTrade
  module Api
    module V2
      module Platform
        class PaymentsController < ResourceController
          include NumberResource

          private

          def model_class
            PallasTrade::Payment
          end

          def resource_serializer
            PallasTrade.api.platform_payment_serializer
          end
        end
      end
    end
  end
end
