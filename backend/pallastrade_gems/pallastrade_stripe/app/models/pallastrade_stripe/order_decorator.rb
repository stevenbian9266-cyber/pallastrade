module PallasTradeStripe
  module OrderDecorator
    def self.prepended(base)
      base.store_accessor :private_metadata, :stripe_tax_calculation_id
    end
  end
end

PallasTrade::Order.prepend(PallasTradeStripe::OrderDecorator)
