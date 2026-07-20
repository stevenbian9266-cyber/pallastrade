module PallasTradeAdyen
  module StoreControllerDecorator
    def self.prepended(base)
      base.helper PallasTradeAdyen::BaseHelper
    end
  end
end

PallasTrade::StoreController.prepend(PallasTradeAdyen::StoreControllerDecorator) if defined?(PallasTrade::StoreController)
