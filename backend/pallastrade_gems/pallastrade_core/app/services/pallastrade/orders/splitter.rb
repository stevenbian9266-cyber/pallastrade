# PALLAS-CUSTOM: 多订单拆分（PRD-20260823-checkout-多订单拆分与合并支付）
#
# Splits an unpaid order into multiple new orders by partitioning its line items.
# Used by:
#   - admin manual split (POST /api/v3/admin/orders/:id/split)
#   - checkout-time auto split (by warehouse) — see Checkout::SplitOrders
#
# The source order keeps the line items that were not assigned to any group.
# New orders inherit store/user/channel/currency/addresses and start in `cart`
# state so the normal checkout pipeline (shipments, adjustments, totals) rebuilds.
module PallasTrade
  module Orders
    class Splitter
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order] the source order (must not be completed or paid)
      # @param groups [Hash<Symbol/String, Array<String,Integer>>] group key → line item ids
      # @return [ServiceResult<Array<PallasTrade::Order>>]
      def call(order:, groups:)
        ApplicationRecord.transaction do
          return failure(order, PallasTrade.t(:order_not_splittable)) unless splittable?(order)
          return failure(order, PallasTrade.t(:no_split_groups)) if groups.blank?

          new_orders = groups.filter_map do |_key, line_item_ids|
            build_split_order(order, Array(line_item_ids))
          end

          return failure(order, PallasTrade.t(:no_split_line_items)) if new_orders.empty?

          # Recalculate source + children totals/shipments
          order.reload
          PallasTrade::OrderUpdater.new(order).update
          new_orders.each { |o| PallasTrade::OrderUpdater.new(o).update }

          success(new_orders)
        end
      end

      private

      def splittable?(order)
        !order.completed? && !order.canceled? && order.payments.completed.none?
      end

      def build_split_order(source, line_item_ids)
        line_items = source.line_items.where(id: line_item_ids).to_a
        return nil if line_items.empty?

        split_order = PallasTrade::Order.new(
          store: source.store,
          user: source.user,
          channel: source.channel,
          market: source.market,
          currency: source.currency,
          email: source.email,
          locale: source.locale,
          bill_address: source.bill_address,
          ship_address: source.ship_address,
          split_from: source,
          last_ip_address: source.last_ip_address,
          created_by: source.created_by
        )
        split_order.save!

        # Move the selected line items onto the new order (triggers inventory/adjustment recalc)
        line_items.each { |li| li.update!(order: split_order) }

        split_order
      end
    end
  end
end
