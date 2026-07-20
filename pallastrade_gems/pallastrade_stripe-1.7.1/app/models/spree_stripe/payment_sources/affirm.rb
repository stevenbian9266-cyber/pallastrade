module SpreeStripe
  module PaymentSources
    class Affirm < ::PallasTrade::PaymentSource
      def actions
        %w[credit]
      end
    end
  end
end
