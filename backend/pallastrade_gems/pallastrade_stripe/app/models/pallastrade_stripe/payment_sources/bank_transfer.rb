module PallasTradeStripe
  module PaymentSources
    class BankTransfer < ::PallasTrade::PaymentSource
      def actions
        %w[credit]
      end

      def self.display_name
        PallasTrade.t(:bank_transfer)
      end

      def name
        PallasTrade.t(:bank_transfer)
      end
    end
  end
end
