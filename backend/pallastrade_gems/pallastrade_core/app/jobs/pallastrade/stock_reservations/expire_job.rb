module PallasTrade
  module StockReservations
    # INV-P3-1 (PRD-20260905-shipping-...):
    # ExpireJob —— RESERVED 且已过 TTL 的 Reservation 流转为 EXPIRED（不再硬删除）。
    # 幂等：只处理 state=reserved 的行；重复执行安全。历史终态行保留（审计/evidence）。
    class ExpireJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.stock_reservations

      def perform
        PallasTrade::StockReservation.expired.in_batches(of: 1_000) do |batch|
          batch.update_all(state: 'expired', expired_at: Time.current, updated_at: Time.current)
        end
      end
    end
  end
end
