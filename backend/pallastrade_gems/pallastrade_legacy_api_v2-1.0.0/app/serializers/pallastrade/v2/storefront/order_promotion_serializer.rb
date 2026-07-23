# this is actually a serializer for PallasTrade::OrderPromotion, not PallasTrade::Promotion
# we should fix this in the future
module PallasTrade
  module V2
    module Storefront
      class OrderPromotionSerializer < BaseSerializer
        set_id     :promotion_id
        set_type   :promotion

        attributes :name, :description, :amount, :display_amount, :code, :public_metadata
      end
    end
  end
end
