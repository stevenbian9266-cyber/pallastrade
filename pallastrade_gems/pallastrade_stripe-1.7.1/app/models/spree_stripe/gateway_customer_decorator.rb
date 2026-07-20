module SpreeStripe
  module GatewayCustomerDecorator
    def self.prepended(base)
      base.scope :stripe, -> { joins(:payment_method).where("#{PallasTrade::PaymentMethod.table_name}.type" => SpreeStripe::Gateway.to_s) }
    end
  end
end

PallasTrade::GatewayCustomer.prepend(SpreeStripe::GatewayCustomerDecorator)
