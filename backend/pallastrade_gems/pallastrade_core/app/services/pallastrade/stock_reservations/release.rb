module PallasTrade
  module StockReservations
    # INV-P3-1 (PRD-20260905-shipping-...):
    # Release —— 未消费 Reservation 的主动释放（RESERVED → RELEASED），不再硬删除。
    # 语义：释放占用的可售库存（undo reservation），区别于 Commit（consume 后的事实确认）。
    #
    # 幂等：只处理 state=reserved 的行；终态行 no-op。
    # 注意：PAID 交易的普通 Release 属违禁路径（INV-I09），由调用方/PaymentFact 门控（P3-4 接）。
    class Release
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      # @param transaction [PallasTrade::CommerceTransaction, nil] 按 transaction 归属释放（可选）
      # @param reason [String, nil] release_reason（审计）
      def call(order: nil, transaction: nil, reason: nil)
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
