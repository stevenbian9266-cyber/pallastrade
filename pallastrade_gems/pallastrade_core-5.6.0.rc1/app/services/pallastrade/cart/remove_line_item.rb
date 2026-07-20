module PallasTrade
  module Cart
    class RemoveLineItem
      prepend PallasTrade::ServiceModule::Base

      def call(order:, line_item:, options: nil)
        options ||= {}
        ActiveRecord::Base.transaction do
          order.line_items.destroy(line_item)

          # LineItem dependent: :destroy removes its own reservation row;
          # remaining items may need a fresh reservation pass when in checkout.
          if order.in_checkout? && order.line_items.any?
            result = PallasTrade::StockReservations::Reserve.call(order: order)
            raise PallasTrade::StockReservations::InsufficientStockError.new(nil, result.error.to_s) if result.failure?
          end

          PallasTrade.cart_recalculate_service.new.call(order: order,
                                                  line_item: line_item,
                                                  options: options)
        end
        success(line_item)
      rescue PallasTrade::StockReservations::InsufficientStockError => e
        failure(line_item, e.message)
      end
    end
  end
end
