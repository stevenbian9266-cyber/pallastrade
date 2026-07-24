module PallasTradeAdyen
  module PaymentSources
    class Gcash < ::PallasTrade::PaymentSource
      store_accessor :public_metadata, :payment_reference

      def actions
        %w[credit void]
      end

      def self.display_name
        'GCash'
      end

      def display_payment_info
        "GCash: #{payment_reference}"
      end
    end
  end
end
