module PallasTradePaypalCheckout
  module OrderDecorator
    def self.prepended(base)
      base.store_accessor :private_metadata, :paypal_id

      base.has_many :paypal_checkout_orders, class_name: 'PallasTradePaypalCheckout::Order', dependent: :destroy, foreign_key: :order_id
    end
  end
end

PallasTrade::Order.prepend(PallasTradePaypalCheckout::OrderDecorator)
