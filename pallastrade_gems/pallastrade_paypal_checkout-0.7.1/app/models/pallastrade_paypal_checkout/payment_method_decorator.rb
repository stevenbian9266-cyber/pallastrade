module PallasTradePaypalCheckout
  module PaymentMethodDecorator
    PAYPAL_CHECKOUT_TYPE = 'PallasTradePaypalCheckout::Gateway'.freeze unless defined?(PAYPAL_CHECKOUT_TYPE)

    def self.prepended(base)
      base.scope :paypal_checkout, -> { where(type: PAYPAL_CHECKOUT_TYPE) }
    end

    def paypal_checkout?
      type == PAYPAL_CHECKOUT_TYPE
    end
  end
end

PallasTrade::PaymentMethod.prepend(PallasTradePaypalCheckout::PaymentMethodDecorator)
