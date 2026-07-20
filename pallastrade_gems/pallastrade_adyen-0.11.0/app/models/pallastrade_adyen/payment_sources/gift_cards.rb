module PallasTradeAdyen
  module PaymentSources
    class GiftCards < ::PallasTrade::PaymentSource
      store_accessor :public_metadata, :payment_reference

      def actions
        %w[credit void]
      end

      def self.display_name
        'Gift cards'
      end

      def display_payment_info
        "Gift cards: #{payment_reference}"
      end
    end
  end
end
