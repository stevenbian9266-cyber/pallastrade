# frozen_string_literal: true

# PALLAS-CUSTOM: D10（PRD-20260915-payments-d10-client-config 切片1）——
# 前台密钥下发（业务方案 §68.4 / §76.1）：把 provider 声明的 **publishable 级**凭据
# 组装成 `client_config`，由 Checkout 契约（`payment.available_payment_methods[]`）
# 下发给前台，取代构建期 `NEXT_PUBLIC_*`（换环境/换支付商不再需要重建镜像）。
#
# 安全边界（唯一权威，勿在别处另开一套）：
#   - 只下发 `credential_level(key) == 'publishable'` **且值非空**的偏好；
#   - `secret` / `internal` 级凭据**永不**进入 payload（spec 负向断言）；
#   - `env:NAME` 引用经 `PaymentMethod#resolved_preference` 解析（缺 ENV → 省略该键，
#     不抛错、不落明文）；
#   - 零 provider 网络调用、零额外查询（全部取自已加载的 `PaymentMethod`）。
#
# 短时令牌（如 Stripe 的 publishable 投影）属后续批次：本期 `session_token`
# 恒为 nil，契约先留位；provider 侧签发后覆写 `session_token_for` 即可（不破坏契约）。
module PallasTrade
  module PaymentMethods
    module ClientConfig
      module_function

      # @param payment_method [PallasTrade::PaymentMethod]
      # @return [Hash] { provider:, environment:, publishable: {...}, session_token: nil }
      def call(payment_method)
        {
          provider: provider_key(payment_method),
          environment: payment_method.environment,
          publishable: publishable_credentials(payment_method),
          session_token: session_token_for(payment_method)
        }
      end

      # publishable 级凭据投影（string 键、string 值；空值省略）。
      # @return [Hash{String=>Object}]
      def publishable_credentials(payment_method)
        payment_method.public_preferences.each_with_object({}) do |(key, _raw), out|
          next unless payment_method.credential_level(key) == 'publishable'

          value = payment_method.resolved_preference(key)
          next if blank_value?(value)

          out[key.to_s] = value
        end
      end

      # 契约用的 provider 标识（`stripe` / `adyen` / `paypal_checkout` …），
      # 与既有 payload `type` 字段同源（`Gateway.api_type`）。
      def provider_key(payment_method)
        klass = payment_method.class
        klass.respond_to?(:api_type) ? klass.api_type : klass.name
      end

      # 短时令牌预留位：本期恒 nil（provider 侧签发属后续批次）。
      def session_token_for(_payment_method)
        nil
      end

      def blank_value?(value)
        return true if value.nil?
        return value.strip.empty? if value.is_a?(String)

        value.respond_to?(:empty?) ? value.empty? : false
      end
    end
  end
end
