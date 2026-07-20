module SpreeAdyen
  module PaymentSources
    class Billie < ::PallasTrade::PaymentSource
      def actions
        %w[credit void capture]
      end

      def self.display_name
        'Billie'
      end

      def display_payment_info
        'Billie'
      end
    end
  end
end
