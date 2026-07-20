module SpreeAdyen
  module PaymentSources
    class Blik < Base
      store_accessor :public_metadata

      def actions
        %w[credit void]
      end

      def self.display_name
        'BLIK'
      end
    end
  end
end
