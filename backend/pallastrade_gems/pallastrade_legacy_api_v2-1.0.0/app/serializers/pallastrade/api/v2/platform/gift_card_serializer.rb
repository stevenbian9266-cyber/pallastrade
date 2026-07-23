module PallasTrade
  module Api
    module V2
      module Platform
        class GiftCardSerializer < BaseSerializer
          include ResourceSerializerConcern

          set_type :gift_card

          belongs_to :user, serializer: PallasTrade.api.platform_user_serializer

          has_many :orders, serializer: PallasTrade.api.platform_order_serializer
        end
      end
    end
  end
end
