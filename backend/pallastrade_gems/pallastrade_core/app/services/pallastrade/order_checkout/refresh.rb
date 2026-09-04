# frozen_string_literal: true

# PALLAS-CUSTOM: CHK-P1-2 (PRD-20260903-checkout-chk-p1-1 §12)
module PallasTrade
  module OrderCheckout
    # Checkout Refresh：重新验证报价（Recalculate → 续期 checkout_expires_at）→ 返回最新 CheckoutView。
    # 过期后不能直接以旧报价支付：由 P1-3 的 Payment Start Gate 消费 Expiration/expires_at。
    class Refresh
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      def call(order:)
        return failure(order, 'Order already completed') if order.completed?

        result = PallasTrade::OrderCheckout::Recalculate.call(order: order)
        return result unless result.success?

        refreshed = result.value
        refreshed.update_columns(checkout_expires_at: Time.current + PallasTrade::OrderCheckout::Policies.quote_window)

        success(PallasTrade::OrderCheckout::View.call(order: refreshed.reload))
      end
    end
  end
end
