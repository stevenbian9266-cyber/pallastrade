module SpreeAdyen
  module StoreControllerDecorator
    def self.prepended(base)
      base.helper SpreeAdyen::BaseHelper
    end
  end
end

PallasTrade::StoreController.prepend(SpreeAdyen::StoreControllerDecorator) if defined?(PallasTrade::StoreController)
