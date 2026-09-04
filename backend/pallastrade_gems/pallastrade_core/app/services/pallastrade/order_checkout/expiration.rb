# frozen_string_literal: true

# PALLAS-CUSTOM: CHK-P1-2 (PRD-20260903-checkout-chk-p1-1 §12)
module PallasTrade
  module OrderCheckout
    # 报价过期只读判定（供 P1-3 Payment Start Gate / 展示使用；本包不接入支付链）。
    class Expiration
      # @param order [PallasTrade::Order, nil]
      # @return [Boolean] 无 expires_at 视为未过期（legacy 兼容）；超过则过期。
      def expired?(order: nil)
        return false if order.nil?
        return false if order.checkout_expires_at.nil?

        order.checkout_expires_at <= Time.current
      end

      # @return [ActiveSupport::Duration, nil] 剩余时间
      def expires_in(order: nil)
        return nil if order.nil? || order.checkout_expires_at.nil?

        order.checkout_expires_at - Time.current
      end
    end
  end
end
