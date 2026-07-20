module PallasTrade
  module Variants
    class RemoveLineItemJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.variants

      def perform(line_item:)
        PallasTrade.cart_remove_line_item_service.call(order: line_item.order, line_item: line_item)
      end
    end
  end
end
