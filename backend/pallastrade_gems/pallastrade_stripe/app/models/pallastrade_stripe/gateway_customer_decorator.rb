module PallasTradeStripe
  module GatewayCustomerDecorator
    def self.prepended(base)
      base.scope :stripe, -> { joins(:payment_method).where("#{PallasTrade::PaymentMethod.table_name}.type" => PallasTradeStripe::Gateway.to_s) }
    end
  end
end

PallasTrade::GatewayCustomer.prepend(PallasTradeStripe::GatewayCustomerDecorator)
