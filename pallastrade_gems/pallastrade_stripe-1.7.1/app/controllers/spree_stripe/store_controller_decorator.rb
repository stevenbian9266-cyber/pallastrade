module SpreeStripe
  module StoreControllerDecorator
    def self.prepended(base)
      base.helper SpreeStripe::BaseHelper
    end
  end
end

if defined?(PallasTrade::StoreController)
  PallasTrade::StoreController.prepend(SpreeStripe::StoreControllerDecorator) if defined?(PallasTrade::StoreController)
end
