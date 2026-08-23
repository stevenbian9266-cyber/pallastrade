# PALLAS-CUSTOM: 结账自动拆单（PRD-20260823-checkout-多订单拆分与合并支付）
#
# Splits a cart/order into multiple orders grouped by fulfilment stock location
# (warehouse), then bundles the children into a PaymentGroup so the customer pays
# once for all of them.
#
# Gated by PallasTrade::Config[:auto_split_orders_by_warehouse] (default false) —
# existing single-order checkout flows are untouched until a store enables it.
module PallasTrade
  module Checkout
    class SplitOrders
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order] the cart/order to split
      # @return [ServiceResult<PallasTrade::PaymentGroup>] the group of split orders
      def call(order:)
        ApplicationRecord.transaction do
          return success(order) unless split_required?(order)

          groups = line_items_by_stock_location(order)
          return success(order) if groups.size <= 1

          result = PallasTrade::Orders::Splitter.call(order: order, groups: groups)
          return result if result.failure?

          children = result.value
          group_result = PallasTrade::PaymentGroups::Create.call(
            store: order.store,
            order_ids: children.map(&:id),
            user: order.user
          )
          return group_result if group_result.failure?

          success(group_result.value)
        end
      end

      private

      def split_required?(order)
        PallasTrade::Config[:auto_split_orders_by_warehouse] &&
          !order.completed? && !order.canceled?
      end

      # Groups line-item ids by the stock location the routing strategy assigned
      # them to (respects Preferred Location → Minimize Splits → Default Location).
      def line_items_by_stock_location(order)
        packages = PallasTrade::Stock::Coordinator.new(order).packages
        groups = Hash.new { |h, k| h[k] = [] }

        packages.each do |package|
          package.contents.each do |inventory_unit|
            next unless inventory_unit.respond_to?(:line_item_id) && inventory_unit.line_item_id.present?

            groups["location_#{package.stock_location.id}"] << inventory_unit.line_item_id
          end
        end

        groups
      end
    end
  end
end
