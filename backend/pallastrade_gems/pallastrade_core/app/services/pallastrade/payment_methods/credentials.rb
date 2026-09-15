# frozen_string_literal: true

# PALLAS-CUSTOM: D9（PRD-20260915-payments-d9-支付凭据与环境 切片1）——
# 凭据分级与「环境变量引用」（业务方案 §68.2）。
#
# 分级（沿用既有三档，不新增声明语法）：
#   - `secret`      —— `:password` 型 preference（页面/API 只回掩码）
#   - `publishable` —— provider 声明在 `public_preference_keys` 的偏好（可下发前台）
#   - `internal`    —— 其余偏好（如商户号、域名等非密配置）
# webhook 签名密钥不在此表（独立实体，见 Stripe `WebhookKey`）。
#
# 引用：值形如 `env:STRIPE_SECRET_KEY` → 落库**只存引用**（不落明文），
# 读取侧经 `resolve` 解析为 `ENV['STRIPE_SECRET_KEY']`（缺失返回 nil，不抛错）。
module PallasTrade
  module PaymentMethods
    module Credentials
      ENV_PREFIX = 'env:'
      LEVELS = %w[secret publishable internal].freeze
      ALERT_THRESHOLDS = [30, 7, 1].freeze
      ALERT_LEVELS = (ALERT_THRESHOLDS.map { |days| "#{days}d" } + %w[expired none]).freeze

      module_function

      # @return [Boolean] 是否为 `env:` 引用
      def reference?(value)
        value.is_a?(String) && value.start_with?(ENV_PREFIX)
      end

      # @return [String, nil] 引用指向的环境变量名
      def reference_name(value)
        return nil unless reference?(value)

        value.delete_prefix(ENV_PREFIX).strip.presence
      end

      # @return [Object] 引用 → ENV 值（缺失 nil）；普通值原样返回
      def resolve(value)
        name = reference_name(value)
        return value if name.nil?

        ENV[name].presence
      end

      # @return [String] secret / publishable / internal
      def level(payment_method, key)
        key_string = key.to_s
        return 'publishable' if payment_method.public_preferences.keys.map(&:to_s).include?(key_string)
        return 'secret' if payment_method.class.password_preference_keys.map(&:to_s).include?(key_string)

        'internal'
      end

      # @param days_left [Integer, nil]
      # @return [String] none / 30d / 7d / 1d / expired（取命中阈值中最高severity）
      def alert_level(days_left)
        return 'none' if days_left.nil?
        return 'expired' if days_left.negative?

        hit = ALERT_THRESHOLDS.select { |threshold| days_left <= threshold }.min
        hit ? "#{hit}d" : 'none'
      end

      # @return [Date, nil] 宽松解析（ISO 日期 / 时间戳 / "YYYY-MM-DD"）；非法返回 nil
      def parse_date(value)
        return nil if value.blank?
        return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
