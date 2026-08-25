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
      # @param cascade [Boolean] 父子单联动（PRD-20260824 FR-041）：取消父订单时联动取消其全部子订单
      #   （各自记录取消原因、按各自支付/库存处理）；false 时仅取消指定订单（可对单个子订单取消）。
      # @return [PallasTrade::ServiceModule::Result]
      def call(order:, canceler: nil, canceled_at: nil,
               reason: DEFAULT_REASON, note: nil,
               restock_items: false, refund_payments: false, refund_amount: nil,
               notify_customer: false, cascade: true)
        canceled_at ||= Time.current

        # PALLAS-CUSTOM: 父子单联动（FR-041）— 父取消 → 子订单联动处理；仅取消子订单时 cascade: false
        targets = cascade ? ([order] + order.children.to_a).uniq : [order]

        order.transaction do
          targets.each do |target|
            target_refund_amount = if refund_payments && refund_amount.nil?
                                     target.payment_total
                                   else
                                     refund_amount
                                   end

            target.cancellations.create!(
              reason: reason,
              note: note,
              restock_items: restock_items,
              refund_payments: refund_payments,
              refund_amount: target_refund_amount,
              notify_customer: notify_customer,
              canceled_by: canceler,
              created_at: canceled_at
            )

            changes = { canceled_at: canceled_at }
            changes[:canceler_id] = canceler.id if canceler.present?
            target.update_columns(changes)
            target.cancel!
          end
        end

        order.publish_event('order.canceled', order.event_payload.merge(notify_customer: notify_customer))
        success(targets)
      rescue ActiveRecord::RecordInvalid, StateMachines::InvalidTransition
        failure(order)
      end
    end
  end
end
