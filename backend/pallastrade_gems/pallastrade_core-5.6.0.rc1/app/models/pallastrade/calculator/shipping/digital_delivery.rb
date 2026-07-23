require_dependency 'pallastrade/shipping_calculator'

module PallasTrade
  module Calculator::Shipping
    class DigitalDelivery < ShippingCalculator
      preference :amount, :decimal, default: 0
      preference :currency, :string, default: -> { PallasTrade::Store.default.default_currency }

      def self.description
        PallasTrade.t('digital.digital_delivery')
      end

      def compute_package(_package = nil)
        preferred_amount
      end

      def available?(package)
        package.contents.all? { |content| content.variant.digital? }
      end
    end
  end
end
