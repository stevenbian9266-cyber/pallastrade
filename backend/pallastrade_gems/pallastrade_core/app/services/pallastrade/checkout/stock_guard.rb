# PALLAS-CUSTOM: 下单库存校验 + 锁库存双模式（PRD-20260824-checkout-正向订单-逆向订单链路重构或优化）
#
# FR-015：下单校验库存（对每个行项目校验可售库存，不足拦截并提示可售量）。
# FR-016：锁库存双模式（后台配置 stock_reservation_strategy）：
#   - 'order'（默认）：下单即锁定（StockReservations::Reserve hold: true）
#   - 'payment'：下单仅校验不锁定，支付成功后再锁定/扣减（Reserve hold: false）
module PallasTrade
  module Checkout
    class StockGuard
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      # @return [ServiceResult<PallasTrade::Order>] failure 时 error.value = { code:, message: }
      def call(order:)
        return failure(order, { code: :order_required, message: t(:order_required) }) if order.blank?

        strategy = stock_strategy(order)
        hold = strategy != 'payment'

        result = PallasTrade::StockReservations::Reserve.call(order: order, hold: hold)
        return success(order) if result.success?

        failure(order, { code: :insufficient_stock, message: result.error.to_s })
      end

      private

      # 店铺级覆盖 > 全局配置 > 默认 'order'
      def stock_strategy(order)
        store = order.store
        value = if store&.respond_to?(:preferred_stock_reservation_strategy)
                  store.preferred_stock_reservation_strategy
                end
        value = PallasTrade::Config[:stock_reservation_strategy] if value.blank?
        value.to_s.presence || 'order'
      end

      def t(key)
        I18n.t("pallastrade.checkout_guard.#{key}", default: "checkout_guard_#{key}")
      end
    end
  end
end
