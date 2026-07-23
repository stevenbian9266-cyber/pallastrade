module PallasTrade
  module V2
    module Storefront
      class OrderSerializer < CartSerializer
        include PallasTrade::Api::V2::PublicMetafieldsConcern

        set_type :order
      end
    end
  end
end
