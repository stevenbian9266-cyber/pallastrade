module PallasTrade
  module Cart
    class SetQuantity
      prepend PallasTrade::ServiceModule::Base

      def call(order:, line_item:, quantity: nil)
        ActiveRecord::Base.transaction do
          run :change_item_quantity
          run :handle_stock_reservations
          run PallasTrade.cart_recalculate_service
        end
      end

      private

      def change_item_quantity(order:, line_item:, quantity: nil)
        return failure(line_item) unless line_item.update(quantity: quantity)

        success(order: order, line_item: line_item)
      end

      def handle_stock_reservations(order:, line_item:)
        if order.in_checkout?
          result = PallasTrade::StockReservations::Reserve.call(order: order, validate_only: validate_only_reservations?)
          return failure(line_item, result.error) if result.failure?
        end

        success(order: order, line_item: line_item)
      end

      # P8：:payment 锁存模式——cart 操作只校验不落 reservation
      def validate_only_reservations?
        PallasTrade::Config[:stock_reservation_strategy].to_s == 'payment'
      end
    end
  end
end
