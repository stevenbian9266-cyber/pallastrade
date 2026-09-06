# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4 review 批1 (2026-09-06, bugfix C1) —— 组合 Payment after_commit 崩溃修复。
# 组合支付（PaymentCombinations::Settlement）的 Payment 挂组合、order_id=nil；complete! 提交后
# after_commit 触发，`order.paid?` 对 nil order 抛 NoMethodError，异常从 Settlement 冒出并中断
# Transactions::Finalize（成员订单完成前）。
module PallasTrade
  class Payment < PallasTrade.base_class
    # Publishes custom payment events beyond basic lifecycle events.
    #
    # Events:
    # - payment.paid: Payment was completed
    # - order.paid: Order is fully paid (no outstanding balance)
    #
    module CustomEvents
      extend ActiveSupport::Concern

      included do
        after_commit :publish_payment_paid_event, on: :update, if: :should_publish_paid_event?
      end

      private

      def should_publish_paid_event?
        return false unless PallasTrade::Events.enabled?
        return false unless state_previously_changed?

        state_previous_change&.last == 'completed'
      end

      def publish_payment_paid_event
        publish_event('payment.paid')
        publish_order_paid_event if order&.paid?
      end

      def publish_order_paid_event
        order.publish_event('order.paid')
      end
    end
  end
end
