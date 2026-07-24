module PallasTradeStripe
  module StoreControllerDecorator
    def self.prepended(base)
      base.helper PallasTradeStripe::BaseHelper
    end
  end
end

if defined?(PallasTrade::StoreController)
  PallasTrade::StoreController.prepend(PallasTradeStripe::StoreControllerDecorator) if defined?(PallasTrade::StoreController)
end
