module PallasTradePaypalCheckout
  module PaymentSources
    class Paypal < ::PallasTrade::PaymentSource
      store_accessor :private_metadata, :email, :name, :account_status, :account_id

      def actions
        %w[credit void]
      end

      def self.display_name
        'PayPal'
      end
    end
  end
end
