module PallasTrade
  module Orders
    class Cancel
      prepend PallasTrade::ServiceModule::Base

      DEFAULT_REASON = 'other'.freeze

      # Cancels an order and records a PallasTrade::OrderCancellation history record.
      # Legacy `canceler:` and `canceled_at:` remain valid; new keywords are additive.
      #
      # @param order [PallasTrade::Order]
      # @param canceler [Object, nil] the user/admin who initiated the cancellation
      # @param canceled_at [Time, nil] timestamp (defaults to Time.current)
      # @param reason [String] one of PallasTrade::OrderCancellation::REASONS
      # @param note [String, nil] staff-facing note
      # @param restock_items [Boolean] whether to return inventory
      # @param refund_payments [Boolean] whether to refund captured payments
      # @param refund_amount [BigDecimal, Numeric, nil] amount to refund;
      #   when refund_payments is true and this is nil, defaults to order.payment_total
      # @param notify_customer [Boolean] hint for subscribers
      # @return [PallasTrade::ServiceModule::Result]
      # rubocop:disable Metrics/ParameterLists -- 既有 P7 服务签名，保持调用方兼容
      def call(order:, canceler: nil, canceled_at: nil,
               reason: DEFAULT_REASON, note: nil,
               restock_items: false, refund_payments: false, refund_amount: nil,
               notify_customer: false)
        # rubocop:enable Metrics/ParameterLists
        canceled_at ||= Time.current
        refund_amount ||= order.payment_total if refund_payments

        # INV-P3-4：取消决策时点的"可释放"判定（after_cancel 会 void/取消已入账支付，
        # 故必须在取消动作前基于权威支付事实捕获，避免把 PAID 误判为未付而错误 Release）。
        release_allowed = !paid_or_in_flight?(order)

        order.transaction do
          order.cancellations.create!(
            reason: reason,
            note: note,
            restock_items: restock_items,
            refund_payments: refund_payments,
            refund_amount: refund_amount,
            notify_customer: notify_customer,
            canceled_by: canceler,
            created_at: canceled_at
          )

          changes = { canceled_at: canceled_at }
          changes[:canceler_id] = canceler.id if canceler.present?
          order.update_columns(changes)
          order.cancel!
        end

        # INV-P3-4 (FR-033/FR-032): 取消后释放"未消费且确未支付"的 RESERVED → RELEASED。
        # PAID / 进行中 attempt（可能 webhook 迟到变 PAID）→ 不自动 Release（INV-I09）。
        release_unpaid_reservations(order) if release_allowed

        order.publish_event('order.canceled', order.event_payload.merge(notify_customer: notify_customer))
        success(order.reload)
      rescue ActiveRecord::RecordInvalid, StateMachines::InvalidTransition
        failure(order)
      end

      private

      # 仅当订单确未支付（无 completed payment / payment_total=0）且无进行中支付 attempt
      # 时释放 reservation；COMMITTED 行（售后/已完成）天然不受 Release 影响（FR-034）。
      def release_unpaid_reservations(order)
        return if paid_or_in_flight?(order)

        PallasTrade::StockReservations::Release.call(order: order, reason: 'order_canceled')
      end

      def paid_or_in_flight?(order)
        return true if order.payment_total.to_f.positive?
        return true if order.payments.valid.completed.exists?

        transaction = PallasTrade::CommerceTransaction.active_for_order(order)
        transaction.present? && transaction.payment_sessions.exists?
      end
    end
  end
end
