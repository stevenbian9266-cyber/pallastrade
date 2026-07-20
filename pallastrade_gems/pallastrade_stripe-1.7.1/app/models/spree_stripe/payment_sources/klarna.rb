module SpreeStripe
  module PaymentSources
    class Klarna < ::PallasTrade::PaymentSource
      def actions
        %w[credit]
      end
    end
  end
end
