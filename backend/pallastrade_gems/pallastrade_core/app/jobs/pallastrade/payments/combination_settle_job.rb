# frozen_string_literal: true

# PALLAS-CUSTOM: 合并支付补偿队列（PRD-20260827 P4）
# PaymentCombinations::Complete 中个别订单完成失败时入队：重试完成该成员订单。
# 幂等：订单已完成 / 组合已取消 → 直接跳过。重试耗尽（discard）后订单保留 balance_due 供人工介入。
module PallasTrade
  module Payments
    class CombinationSettleJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.payment_webhooks

      retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
      retry_on ActiveRecord::LockWaitTimeout, wait: 5.seconds, attempts: 3
      discard_on ActiveRecord::RecordNotFound

      def perform(combination_id, order_id)
        combination = PallasTrade::PaymentCombination.find(combination_id)
        order = PallasTrade::Order.find(order_id)

        # 幂等 / 守卫：订单已完成、组合未成功、订单已取消 → 无需处理
        return if order.completed? || order.canceled?
        return unless combination.succeeded?

        result = PallasTrade::Dependencies.checkout_complete_service.constantize.call(order: order)
        return if order.reload.completed?

        # 仍失败：保持 balance_due（资金已入账，订单待人工介入），不无限重试
        order.update_column(:payment_state, 'balance_due') unless order.payment_state == 'balance_due'
      end
    end
  end
end
