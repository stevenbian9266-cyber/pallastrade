# frozen_string_literal: true

# PALLAS-CUSTOM: 组合成员订单完成 primitive 分流（RISK-01, 2026-09-04）
#
# 背景：PaymentCombinations::Complete 阶段 2 与 CombinationSettleJob 原统一调用
# legacy `Checkout::Complete`（next-until-complete）。该 primitive 只对 legacy
# checkout 状态（cart→address→…→complete）有效；对 standard-flow 成员
# （Carts::Submit 产物，state=pending/paid）没有 `from: pending` 迁移 →
# Checkout::Complete 返回 failure、订单停留 pending → 组合资金已入账但成员
# 永不完成（balance_due + CompensationJob 永久重试失败）。见
# docs/research/RESEARCH-20260904-txn-p2-0... §10（TXN-P2-0 RISK-01 运行时验证）。
#
# 分流：
#   - standard flow 成员 → `Carts::Complete`（canonical：pay!+finalize!；其
#     complete_standard_order! 已支持 payment_splits captured>0 放行，无需本地 payment）
#   - legacy 成员（存量）→ `Checkout::Complete`（COMPATIBILITY ADAPTER，行为不变）
#
# 幂等：order 已 completed → 直接 success（对齐两 primitive 既有入口守卫）。
module PallasTrade
  module Payments
    class CombinationMemberComplete
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      # @return [PallasTrade::ServiceModule::Result]
      def call(order:)
        return success(order) if order.nil? || order.completed?

        if order.standard_flow?
          PallasTrade::Dependencies.carts_complete_service.constantize.call(cart: order)
        else
          PallasTrade::Dependencies.checkout_complete_service.constantize.call(order: order)
        end
      end
    end
  end
end
