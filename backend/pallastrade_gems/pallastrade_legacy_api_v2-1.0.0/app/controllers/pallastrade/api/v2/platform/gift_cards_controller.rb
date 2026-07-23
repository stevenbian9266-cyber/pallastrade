module PallasTrade
  module Api
    module V2
      module Platform
        class GiftCardsController < ResourceController
          private

          def model_class
            PallasTrade::GiftCard
          end

          def permitted_resource_params
            params.require(:gift_card).permit(permitted_gift_card_attributes)
          end

          def resource_serializer
            PallasTrade.api.platform_gift_card_serializer
          end
        end
      end
    end
  end
end
