module SpreeAdyen
  module PaymentSources
    class Atome < ::PallasTrade::PaymentSource
      def actions
        %w[credit void]
      end

      def self.display_name
        'Atome'
      end

      def display_payment_info
        'Atome'
      end
    end
  end
end
