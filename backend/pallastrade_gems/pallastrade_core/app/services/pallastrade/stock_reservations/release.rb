module PallasTrade
  module StockReservations
    class Release
      prepend PallasTrade::ServiceModule::Base

      def call(order:)
        PallasTrade::StockReservation.where(order_id: order.id).delete_all
        success(order)
      end
    end
  end
end
