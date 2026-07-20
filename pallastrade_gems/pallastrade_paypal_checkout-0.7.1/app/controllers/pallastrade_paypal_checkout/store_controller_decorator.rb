module PallasTradePaypalCheckout
  module StoreControllerDecorator
    def self.prepended(base)
      base.helper PallasTradePaypalCheckout::BaseHelper
    end
  end
end

PallasTrade::StoreController.prepend(PallasTradePaypalCheckout::StoreControllerDecorator) if defined?(PallasTrade::StoreController)
