module PallasTrade
  module Checkout
    class Next
      prepend PallasTrade::ServiceModule::Base

      def call(order:)
        return success(order.reload) if order.next

        failure(order)
      end
    end
  end
end
