module PallasTrade
  module StockReservations
    class ExpireJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.stock_reservations

      def perform
        PallasTrade::StockReservation.expired.in_batches(of: 1_000).delete_all
      end
    end
  end
end
