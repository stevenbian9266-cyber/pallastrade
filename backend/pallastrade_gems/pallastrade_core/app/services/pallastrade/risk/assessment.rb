# PALLAS-CUSTOM: 风控评估（PRD-20260824-checkout-正向订单-逆向订单链路重构或优化）
#
# 下单前风控评估（FR-003 / FR-053）：
# - 可配置评估钩子：PallasTrade::Config[:risk_assessment] = ->(user:, order_params:) { nil | { code:, message: } }
#   （nil = 通过；返回 hash = 拦截，含结构化 code 与可展示 message）
# - 默认规则：下单频率限制（PallasTrade::Config[:order_frequency_limit_per_minute]，0 = 关闭）
# - 命中拦截不抛异常，返回 failure(user, { code:, message: })
module PallasTrade
  module Risk
    class Assessment
      prepend PallasTrade::ServiceModule::Base

      # @param user [PallasTrade.user_class, nil] 当前用户（nil 视为未登录）
      # @param order_params [Hash] 下单上下文（商品/数量等，供规则钩子使用）
      # @return [ServiceResult<PallasTrade.user_class>]
      def call(user:, order_params: {})
        return failure(nil, { code: :login_required, message: t(:login_required) }) if user.blank?

        result = run_assessment(user, order_params)
        return success(user) if result.blank?

        failure(user, { code: result[:code] || :risk_blocked, message: result[:message] || t(:risk_blocked) })
      end

      private

      def run_assessment(user, order_params)
        hook = PallasTrade::Config[:risk_assessment]
        return hook.call(user: user, order_params: order_params) if hook.respond_to?(:call)

        default_rule(user)
      end

      # 默认风控规则：下单频率限制（防刷单）
      def default_rule(user)
        threshold = PallasTrade::Config[:order_frequency_limit_per_minute].to_i
        return nil if threshold <= 0

        recent = user.orders.where('created_at > ?', 1.minute.ago).count
        return nil if recent < threshold

        { code: :too_many_orders, message: t(:too_many_orders) }
      end

      def t(key)
        I18n.t("pallastrade.risk.#{key}", default: "risk_#{key}")
      end
    end
  end
end
