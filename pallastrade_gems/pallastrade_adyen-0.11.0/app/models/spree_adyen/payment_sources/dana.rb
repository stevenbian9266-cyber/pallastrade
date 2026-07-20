module SpreeAdyen
  module PaymentSources
    class Dana < ::PallasTrade::PaymentSource
      def actions
        %w[credit void]
      end

      def self.display_name
        'DANA'
      end

      def display_payment_info
        'DANA'
      end
    end
  end
end
