module SpreePaypalCheckout
  module StoreControllerDecorator
    def self.prepended(base)
      base.helper SpreePaypalCheckout::BaseHelper
    end
  end
end

PallasTrade::StoreController.prepend(SpreePaypalCheckout::StoreControllerDecorator) if defined?(PallasTrade::StoreController)
