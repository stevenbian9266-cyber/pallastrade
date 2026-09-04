# frozen_string_literal: true

# PALLAS-CUSTOM: CHK-P1-1B (PRD-20260903-checkout-chk-p1-1 §12)
# Order Checkout Mutation Facade —— 只 WRAP 既有 Domain Services，禁止复制逻辑。
module PallasTrade
  module OrderCheckout
    # 更新订单收货地址（复用 Orders::UpdateShippingAddress 地址赋值/sync 语义）
    # → 返回最新 CheckoutView。不重置状态机（由被 WRAP 服务语义保证）。
    class UpdateAddress
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      # @param params [Hash, ActionController::Parameters] 支持 :shipping_address_id /
      #   :shipping_address { ... }（与 Orders::UpdateShippingAddress 同参）
      def call(order:, params:)
        return failure(order, 'Order already completed') if order.completed?

        result = PallasTrade::Orders::UpdateShippingAddress.call(order: order, params: params)
        return result unless result.success?

        # CHK-P1-2：地址变化 → tax/promo/shipment recalc + price_version 刷新
        recalculated = PallasTrade::OrderCheckout::Recalculate.call(order: result.value)
        return recalculated unless recalculated.success?

        success(PallasTrade::OrderCheckout::View.call(order: recalculated.value))
      end
    end
  end
end
