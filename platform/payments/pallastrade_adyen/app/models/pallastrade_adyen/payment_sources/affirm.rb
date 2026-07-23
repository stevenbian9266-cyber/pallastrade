module PallasTradeAdyen
  module PaymentSources
    class Affirm < ::PallasTrade::PaymentSource
      def actions
        %w[credit void capture]
      end

      def self.display_name
        'Affirm'
      end

      def display_payment_info
        'Affirm'
      end
    end
  end
end
