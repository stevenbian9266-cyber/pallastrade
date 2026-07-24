module PallasTradeAdyen
  module PaymentSources
    class AchDirectDebit < ::PallasTrade::PaymentSource
      def actions
        %w[credit void]
      end

      def self.display_name
        'ACH Direct Debit'
      end

      def display_payment_info
        'ACH Direct Debit'
      end
    end
  end
end
