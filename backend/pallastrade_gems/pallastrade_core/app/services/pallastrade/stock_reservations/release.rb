module PallasTrade
  module StockReservations
    # INV-P3-1 (PRD-20260905-shipping-...):
    # Release —— 未消费 Reservation 的主动释放（RESERVED → RELEASED），不再硬删除。
    # 语义：释放占用的可售库存（undo reservation），区别于 Commit（consume 后的事实确认）。
    #
    # 幂等：只处理 state=reserved 的行；终态行 no-op。
    #
    # INV-P3 审计收口 D7 (2026-09-05)：**PAID 防御 guard**——已捕获支付/已完成的订单
    # （payment_total>0 / completed_at / state in paid|complete）禁止普通 Release
    # （INV-I09：资金已付 → 库存已承诺，只应走 Commit 或 Recovery）。调用方如需在
    # 明确语义下强制释放（如退款后运维），传 allow_paid: true。
    class Release
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      # @param transaction [PallasTrade::CommerceTransaction, nil] 按 transaction 归属释放（可选）
      # @param reason [String, nil] release_reason（审计）
      # @param allow_paid [Boolean] 明确授权下允许对 PAID 订单释放（默认 false）
      def call(order: nil, transaction: nil, reason: nil, allow_paid: false)
        paid = affected_orders(order: order, transaction: transaction).any? { |o| paid_order?(o) }
        if paid && !allow_paid
          return failure(order || transaction, {
                           code: 'reservation_release_blocked_paid',
                           message: 'Release of reservations on a paid/completed order is ' \
                                    'blocked (INV-I09); resolve via Commit/Recovery or ' \
                                    'pass allow_paid: true'
                         })
        end

        scope = PallasTrade::StockReservation.reserved
        scope = scope.where(order_id: order.id) if order
        scope = scope.where(commerce_transaction_id: transaction.id) if transaction
        return success(order || transaction) if scope.nil? || scope.empty?

        scope.find_each do |reservation|
          release_reservation(reservation, reason)
        end

        success(order || transaction)
      end

      private

      def affected_orders(order: nil, transaction: nil)
        return Array.wrap(order) if order
        return [] if transaction.nil?

        transaction.transaction_orders.includes(:order).filter_map(&:order).uniq
      end

      def paid_order?(order)
        return false if order.nil?

        order.payment_total.to_f.positive? || order.completed_at.present? ||
          %w[paid complete].include?(order.state)
      end

      def release_reservation(reservation, reason)
        reservation.with_lock do
          next unless reservation.state == 'reserved'

          reservation.release_reason = reason if reason.present?
          reservation.save! if reservation.release_reason_changed?
          reservation.release!
        end
      end
    end
  end
end
