module PallasTradeStripe
  module V2
    module Storefront
      module PaymentMethodSerializerDecorator
        def self.prepended(base)
          base.attribute :publishable_key do |pm|
            pm.try(:preferred_publishable_key)
          end
        end
      end
    end
  end
end

if defined?(PallasTrade::V2::Storefront::PaymentMethodSerializer)
  PallasTrade::V2::Storefront::PaymentMethodSerializer.prepend(PallasTradeStripe::V2::Storefront::PaymentMethodSerializerDecorator)
end
