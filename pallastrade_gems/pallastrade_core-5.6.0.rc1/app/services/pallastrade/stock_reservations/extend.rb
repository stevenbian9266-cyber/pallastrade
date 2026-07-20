module PallasTrade
  module StockReservations
    class Extend
      prepend PallasTrade::ServiceModule::Base

      def call(order:)
        return success(order) unless PallasTrade::Config[:stock_reservations_enabled]

        expires_at = Time.current + PallasTrade::StockReservation.ttl_for(order)

        PallasTrade::StockReservation
          .where(order_id: order.id)
          .update_all(expires_at: expires_at, updated_at: Time.current)

        success(order)
      end
    end
  end
end
