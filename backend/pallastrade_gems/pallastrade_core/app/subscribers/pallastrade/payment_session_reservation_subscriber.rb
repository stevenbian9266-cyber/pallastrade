# frozen_string_literal: true

module PallasTrade
  # INV-P3 审计收口 D3 (2026-09-05):
  # 支付尝试进入 processing（PSP/3DS 认证开始）时，刷新该订单/交易 RESERVED 行的 TTL
  # （StockReservations::Extend）——兑现冻结策略 S5/FR-039/AC-3020：合法 active payment
  # execution 不得无保护地超过 reservation validity。
  #
  # 覆盖窗口说明：
  #   - Transactions::Start 每次 (re)reserve 已把 expires_at 重置为 now+TTL（Resume 同路径）；
  #   - 本订阅方在 session pending→processing（认证/3DS 开始）时再续一次 TTL，覆盖
  #     Start 之后、payment confirm 之前的长时间 PSP 认证窗口；
  #   - 若仍超 TTL（provider 窗口 > TTL 且期间无新事件），ExpireJob 按 TTL 兜底过期 →
  #     PAID 侧由 InventoryFactResolver/Recover 决策（released/expired/ambiguous →
  #     manual_review），不静默超卖（安全收口）。
  class PaymentSessionReservationSubscriber < PallasTrade::Subscriber
    subscribes_to 'payment_session.processing'

    on 'payment_session.processing', :extend_reservations

    private

    def extend_reservations(event)
      session = find_session(event.payload)
      return if session.nil?

      order = session.order
      return if order.nil?

      PallasTrade::StockReservations::Extend.call(
        order: order,
        transaction: session.commerce_transaction
      )
    rescue StandardError => e
      Rails.logger.error("[PaymentSessionReservation] extend failed for session #{session&.id}: #{e.class} #{e.message}")
    end

    # payment_session.processing payload 走 serializer（含 prefixed id）。has_prefix 提供
    # find_by_param（prefix_id gem）；表无 prefixed_id 列，勿用 find_by(prefixed_id:)。
    def find_session(payload)
      id = payload.try(:[], 'id') || payload.try(:[], :id)
      return if id.blank?

      if id.to_s.start_with?('ps_')
        PallasTrade::PaymentSession.find_by_param(id)
      else
        PallasTrade::PaymentSession.find_by(id: id)
      end
    end
  end
end
