module SpreeStripe
  module PaymentSources
    class AfterPay < ::PallasTrade::PaymentSource
      def actions
        %w[credit]
      end

      def self.display_name
        'Afterpay'
      end
    end
  end
end
