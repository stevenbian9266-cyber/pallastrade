# PALLAS-CUSTOM: 下单前置校验（PRD-20260824-checkout-正向订单-逆向订单链路重构或优化）
#
# 统一下单前置校验（FR-001~004）：
# 1. 登录校验：未登录 → failure(nil, { code: :login_required })（前端跳转登录）
# 2. 黑名单校验：用户 blacklisted? → failure(user, { code: :user_blacklisted })
# 3. 风控校验：Risk::Assessment → failure(user, { code: :risk_blocked | :too_many_orders | ... })
#
# 校验在服务端执行（客户端不可绕过）；拦截结果含结构化 code + 可展示 message（FR-004）。
# 下单入口（支付会话创建 / 结账完成 / 合并支付）均调用本服务。
module PallasTrade
  module Checkout
    class Guard
      prepend PallasTrade::ServiceModule::Base

      # @param user [PallasTrade.user_class, nil]
      # @param order_params [Hash] 下单上下文（透传给风控规则）
      # @return [ServiceResult<PallasTrade.user_class>] failure 时 error.value = { code:, message: }
      def call(user:, order_params: {})
        return failure(nil, { code: :login_required, message: t(:login_required) }) if user.blank?
        return failure(user, { code: :user_blacklisted, message: t(:user_blacklisted) }) if user.blacklisted?

        risk = PallasTrade::Risk::Assessment.call(user: user, order_params: order_params)
        return failure(user, risk.error.value) if risk.failure?

        success(user)
      end

      private

      def t(key)
        I18n.t("pallastrade.checkout_guard.#{key}", default: "checkout_guard_#{key}")
      end
    end
  end
end
