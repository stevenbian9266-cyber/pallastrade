module SpreeAdyen
  module PaymentSources
    class Ideal < Base
      store_accessor :public_metadata

      def actions
        %w[credit]
      end

      def self.display_name
        'iDEAL'
      end
    end
  end
end
