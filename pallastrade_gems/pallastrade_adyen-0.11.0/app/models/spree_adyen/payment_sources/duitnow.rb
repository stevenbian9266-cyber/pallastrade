module SpreeAdyen
  module PaymentSources
    class Duitnow < ::PallasTrade::PaymentSource
      def actions
        %w[credit void]
      end

      def self.display_name
        'DuitNow'
      end

      def display_payment_info
        'DuitNow'
      end
    end
  end
end
