module PallasTrade
  module CartLegacy
    class RemoveOutOfStockItems
      prepend ::PallasTrade::ServiceModule::Base

      def call(order:)
        @messages = []
        @warnings = []

        return success([order, @messages, @warnings]) if order.item_count.zero? || order.line_items.none?

        line_items = order.line_items.includes(variant: [:product, :stock_locations, { stock_items: [:stock_location, :active_stock_reservations] }])

        ActiveRecord::Base.transaction do
          line_items.each do |line_item|
            cart_remove_line_item_service.call(order: order, line_item: line_item) if !valid_status?(line_item) || !stock_available?(line_item)
          end
        end

        if @messages.any? # If any line item was removed, reload the order
          success([order.reload, @messages, @warnings])
        else
          success([order, @messages, @warnings])
        end
      end

      private

      # 判废谓词与订单补付重验共用 `Catalog::LineItemAvailability`（单一权威，防口径漂移）。
      def valid_status?(line_item)
        reason = PallasTrade::Catalog::LineItemAvailability.unavailable_reason(line_item)
        return true if reason.nil? || PallasTrade::Catalog::LineItemAvailability.stock_reason?(reason)

        record_removal(line_item, PallasTrade.t('cart_line_item.discontinued', li_name: line_item.name))
        false
      end

      def stock_available?(line_item)
        reason = PallasTrade::Catalog::LineItemAvailability.unavailable_reason(line_item)
        return true if reason.nil? || !PallasTrade::Catalog::LineItemAvailability.stock_reason?(reason)

        record_removal(line_item, PallasTrade.t('cart_line_item.out_of_stock', li_name: line_item.name))
        false
      end

      def record_removal(line_item, message)
        @messages << message
        @warnings << {
          code: 'line_item_removed',
          message: message,
          line_item_id: line_item.prefixed_id,
          variant_id: line_item.variant&.prefixed_id
        }
      end

      def cart_remove_line_item_service
        PallasTrade.cart_remove_line_item_service
      end
    end
  end
end
