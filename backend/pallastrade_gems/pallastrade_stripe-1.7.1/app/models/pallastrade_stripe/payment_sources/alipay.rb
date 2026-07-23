module PallasTradeStripe
  module PaymentSources
    class Alipay < ::PallasTrade::PaymentSource
      def actions
        %w[credit]
      end
    end
  end
end
