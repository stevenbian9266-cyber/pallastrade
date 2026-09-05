module PallasTrade
  module StockReservations
    # INV-P3-1 (PRD-20260905-shipping-...):
    # ExpireJob —— RESERVED 且已过 TTL 的 Reservation 流转为 EXPIRED（不再硬删除）。
    # 幂等：只处理 state=reserved 的行；重复执行安全。历史终态行保留（审计/evidence）。
    #
    # INV-P3 审计收口（2026-09-05）：
    #   - D2：**已捕获支付/已完成的订单不自动过期**——订单已 paid（payment_total>0 /
    #     completed_at / state in paid|complete）时，库存已承诺给该订单，Reservation 必须
    #     保留 RESERVED 直到 canonical Finalize 的 Commit 兜底，避免“物理已消费但行停留
    #     EXPIRED（终态、无法转 COMMITTED）”的竞态。
    #   - D1/FR-053：逐行走状态机 `expire!`（with_lock + state guard），由 after_transition
    #     触发 touch_expired_at + 发布 `inventory.expired` 审计事件（原 update_all 批量旁路
    #     状态机 → 事件缺失）。
    #   - D3：进行中支付会话（pending/processing）的 TTL 刷新由
    #     `payment_session.processing` 订阅方（PaymentSessionReservationSubscriber）负责；
    #     此处仍按 TTL 过期“无支付证据”的兜底，避免会话/预留无限期占用。
    class ExpireJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.stock_reservations

      def perform
        eligible_reservations.find_each(batch_size: 1_000) do |reservation|
          reservation.with_lock do
            reservation.expire! if reservation.state == 'reserved'
          end
        end
      end

      private

      def eligible_reservations
        PallasTrade::StockReservation.expired.joins(:order).
          where.not(pallastrade_orders: { id: guarded_order_ids })
      end

      # D2：带支付/完成证据的订单 → 其 RESERVED 行不参与 TTL 过期（保留至 Commit/Recover）。
      def guarded_order_ids
        PallasTrade::Order.where(
          'payment_total > 0 OR completed_at IS NOT NULL OR state IN (?)',
          %w[paid complete]
        ).select(:id)
      end
    end
  end
end
