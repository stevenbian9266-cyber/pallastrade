module PallasTrade
  module Checkout
    class Complete
      prepend PallasTrade::ServiceModule::Base

      def call(order:)
        # CORE-P5-8: legacy 完成原语使用计数（Retirement Gate 观测，CORE-INV-09）
        PallasTrade::OperationalMetrics.legacy('checkout_complete', order_id: order&.prefixed_id)
        PallasTrade.checkout_next_service.call(order: order) until cannot_make_transition?(order)

        if order.reload.complete?
          success(order)
        else
          failure(order)
        end
      end

      private

      def cannot_make_transition?(order)
        order.complete? || order.errors.present?
      end
    end
  end
end
