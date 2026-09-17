# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片3（PRD-20260917-checkout-d15-切片3；业务方案 §72.1）——
# `Payments::ThreeDSecure::ProviderHint` —— 把「本单要求认证」翻译成**该 provider 认识的参数**。
#
# 语义（诚实优先，**不猜**）：
#   * 能力来自入口目录（`payment_option_catalog[i]['three_d_secure']`，provider 侧声明）：
#     `'supported'` / `'unsupported'`；**缺失按 `unsupported` 处理**；
#   * `supported` + 要求认证 → 下发 `{ 'three_d_secure' => true }`（由 gateway 落到自家参数，
#     例如 Stripe：`payment_method_options.card.request_three_d_secure = 'any'`）；
#   * `unsupported` / 不认识该入口 / 未要求认证 → `{ applied: false, hint: 'none', external_data: {} }`，
#     **绝不发送未知参数**（宁可不下发，也不用 provider 会拒绝或静默忽略的参数）。
#
# 铁律：零 provider I/O（只看本地目录）；不产生资金副作用；不下发任何凭据。
module PallasTrade
  module Payments
    module ThreeDSecure
      class ProviderHint
        prepend PallasTrade::ServiceModule::Base

        SUPPORTED = 'supported'
        UNSUPPORTED = 'unsupported'
        HINT_APPLIED = 'three_d_secure'
        HINT_NONE = 'none'
        EXTERNAL_DATA_KEY = 'three_d_secure'

        PALLAS_TRADE_CONFIG_KEYS = %w[supported unsupported].freeze

        class << self
          def call(**kwargs) = new.call(**kwargs)

          # 入口是否声明「可强制认证」（缺省 = 不支持）
          def option_supported?(payment_method, option_kind)
            return false if payment_method.blank?
            return false unless payment_method.respond_to?(:payment_option_catalog)

            kind = option_kind.to_s.presence
            entry = payment_method.payment_option_catalog.find do |item|
              item['kind'].to_s == kind || item[:kind].to_s == kind
            end
            return false if entry.blank?

            value = entry['three_d_secure'] || entry[:three_d_secure]
            value.to_s.downcase == SUPPORTED
          end
        end

        # @param payment_method [PallasTrade::PaymentMethod]
        # @param option_kind [String, nil] 入口 kind（缺省用 provider 默认入口）
        # @param required [Boolean] 认证需求（来自 `Required`）
        # @return [PallasTrade::ServiceModule::Result] success({ applied:, hint:, option_kind:, external_data: })
        def call(payment_method:, required:, option_kind: nil)
          kind = option_kind.to_s.presence
          kind ||= payment_method.try(:default_option_kind).to_s.presence

          if required != true
            return success(base(kind).merge('reason' => 'not_required'))
          end
          return success(base(kind).merge('reason' => 'no_option_kind')) if kind.blank?

          unless self.class.option_supported?(payment_method, kind)
            return success(base(kind).merge('reason' => 'provider_unsupported'))
          end

          success(
            base(kind).merge(
              'applied' => true,
              'hint' => HINT_APPLIED,
              'reason' => 'applied',
              'external_data' => { EXTERNAL_DATA_KEY => true }
            )
          )
        end

        private

        def base(kind)
          { 'applied' => false, 'hint' => HINT_NONE, 'option_kind' => kind, 'external_data' => {} }
        end
      end
    end
  end
end
