# frozen_string_literal: true

# PALLAS-CUSTOM: CHK-P1-1B (PRD-20260903-checkout-chk-p1-1 §12)
# Order Checkout Mutation Facade —— 只 WRAP 既有 Domain Services，禁止复制逻辑。
module PallasTrade
  module OrderCheckout
    # 更新订单联系信息（email）→ 返回最新 CheckoutView。
    class UpdateContact
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      # @param email [String]
      def call(order:, email:)
        return failure(order, 'Order already completed') if order.completed?

        result = PallasTrade::Orders::UpdateContactInformation.call(order: order, order_params: { email: email })
        return result unless result.success?

        # CHK-P1-2：email 不触发金额 recalc，但 checkout 内容已变 → 版本 +1
        updated = result.value
        updated.update_column(:checkout_version, updated.checkout_version + 1)

        success(PallasTrade::OrderCheckout::View.call(order: updated.reload))
      end
    end
  end
end
