module PallasTrade
  module V2
    module Storefront
      class PaymentSourceSerializer < BaseSerializer
        include PallasTrade::Api::V2::PublicMetafieldsConcern

        belongs_to :payment_method, serializer: PallasTrade.api.storefront_payment_method_serializer
        belongs_to :user, serializer: PallasTrade.api.storefront_user_serializer
      end
    end
  end
end
