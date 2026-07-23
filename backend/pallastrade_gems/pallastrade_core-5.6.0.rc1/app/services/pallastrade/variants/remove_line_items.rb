module PallasTrade
  module Variants
    class RemoveLineItems
      prepend PallasTrade::ServiceModule::Base

      def call(variant:)
        variant.line_items.joins(:order).where(pallastrade_orders: { state: PallasTrade::Order::LINE_ITEM_REMOVABLE_STATES }).find_each do |line_item|
          PallasTrade::Variants::RemoveLineItemJob.perform_later(line_item: line_item)
        end

        success(true)
      end
    end
  end
end
