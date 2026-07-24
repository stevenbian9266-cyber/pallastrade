module PallasTradeAdyen
  module PaymentSources
    class GopayWallet < ::PallasTrade::PaymentSource
      store_accessor :public_metadata, :payment_reference

      def actions
        %w[credit void]
      end

      def self.display_name
        'GoPay'
      end

      def display_payment_info
        "GoPay: #{payment_reference}"
      end
    end
  end
end
