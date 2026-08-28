# frozen_string_literal: true

# PALLAS-CUSTOM: 下单前置校验（PRD-20260828 P8，flag 灰度）
#
# 在 Carts::Complete 支付处理前评估风控规则（PallasTrade::Risk）：
# 黑名单 / 防刷单 / 自定义规则命中 → failure(order, { code:, message: })（统一业务错误，无裸 422）。
# 登录强制已由 Carts::Complete 既有 guest_checkout_disallowed? 覆盖，不在此重复。
# flag：store.preferred_checkout_preflight_enabled 回退 Config[:checkout_preflight_enabled]，默认关闭。
module PallasTrade
  module Checkout
    class Preflight
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      # @return [PallasTrade::ServiceModule::Result] success(order) / failure(order, { code:, message: })
      def call(order:)
        return success(order) unless enabled?(order)

        risk = PallasTrade::Risk.evaluate(order: order)
        return failure(order, risk) if risk

        success(order)
      end

      private

      def enabled?(order)
        store = order&.store
        store&.preferred_checkout_preflight_enabled.presence || PallasTrade::Config[:checkout_preflight_enabled]
      end
    end
  end
end
