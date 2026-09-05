module PallasTrade
  module StockReservations
    class Extend
      prepend PallasTrade::ServiceModule::Base

      # INV-P3-1：只续期 state=reserved 的行（终态行不续期）。
      def call(order: nil, transaction: nil)
        return success(order || transaction) unless PallasTrade::Config[:stock_reservations_enabled]

        expires_at = Time.current + PallasTrade::StockReservation.ttl_for(order)

        scope = PallasTrade::StockReservation.reserved
        scope = scope.where(order_id: order.id) if order
        scope = scope.where(commerce_transaction_id: transaction.id) if transaction

        scope.update_all(expires_at: expires_at, updated_at: Time.current)

        success(order || transaction)
      end
    end
  end
end
