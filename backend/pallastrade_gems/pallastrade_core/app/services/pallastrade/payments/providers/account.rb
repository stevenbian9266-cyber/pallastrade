# frozen_string_literal: true

# PALLAS-CUSTOM: PAY-CORE-P0B（PRD-20260920-checkout 支付核心统一 · 切片 P0-B）——
# 「账户配置」写入原语（业务方案 §2.2）：运营在后台把「本商家账户已开通的支付方式 / 币种 / 国家」
# 写进 `metadata['account']`，让「能力 ∩ 账户 ∩ 市场」收窄真正生效（P0-A 只有只读诊断）。
#
# 白名单（越界值进 `rejected` 并忽略，**不 raise**）：
#   methods    ∈ 能力声明（provider 声明优先 / 能力目录推导）
#   currencies ∈ 店铺支持币种
#   countries  ∈ 店铺市场国家集合（D8 同源）
#
# 语义：
#   - **空选择 = 未声明（nil，该维度不收窄）** —— 避免"全不勾 = 前台全隐藏"的误操作；
#   - 同值重复写入 → `unchanged` = true，**不写库、不审计**（幂等，零副作用）；
#   - 写入走 `update_columns(private_metadata:)`（D9/D11 同范式）：不触发 provider 校验/远端调用。
#   铁律：**零资金副作用** —— 不触碰 Payment / PaymentSession / 账本。
module PallasTrade
  module Payments
    module Providers
      module Account
        DIMENSIONS = %w[methods currencies countries].freeze

        module_function

        # @param payment_method [PallasTrade::PaymentMethod]
        # @return [Hash] { 'ok', 'unchanged', 'account', 'rejected' }
        def write!(payment_method, methods: nil, currencies: nil, countries: nil, actor: nil, now: Time.current)
          allowed = allowed_values(payment_method)
          submitted = { 'methods' => methods, 'currencies' => currencies, 'countries' => countries }

          normalized = {}
          rejected = {}
          DIMENSIONS.each do |dimension|
            values = normalize_list(dimension, submitted[dimension])
            normalized[dimension] = (values & allowed[dimension]).presence
            rejected[dimension] = (values - allowed[dimension]).presence
          end

          current = Config.account_config(payment_method).slice(*DIMENSIONS)
          return result(payment_method, normalized, rejected, unchanged: true) if current == normalized

          persist!(payment_method, normalized, actor: actor, now: now)
          result(payment_method, normalized, rejected, unchanged: false)
        end

        # 可选值来源（后台表单与白名单共用）：
        #   methods    ← 能力声明（声明优先 / 目录推导）
        #   currencies ← 店铺支持币种
        #   countries  ← 店铺市场国家
        # @return [Hash] { 'methods' => [...], 'currencies' => [...], 'countries' => [...] }
        def allowed_values(payment_method)
          capability = Config.capability(payment_method)
          store = payment_method.respond_to?(:store) ? payment_method.store : nil

          {
            'methods' => Array(capability['method_keys']).map { |kind| kind.to_s.downcase }.uniq,
            'currencies' => Array(store&.supported_currencies_list).map { |code| code.to_s.upcase }.uniq,
            'countries' => Array(store&.countries_from_markets).map { |country| country.iso.to_s.upcase }.uniq
          }
        end

        # 归一：methods 小写、其余大写；去空白、去重。非数组 → 空数组（= 未声明）。
        def normalize_list(dimension, raw)
          return [] unless raw.is_a?(Array)

          Array(raw).map { |value| value.to_s.strip }
                     .reject(&:blank?)
                     .map { |value| dimension == 'methods' ? value.downcase : value.upcase }
                     .uniq
        end

        def persist!(payment_method, normalized, actor: nil, now: Time.current)
          metadata = (payment_method.metadata || {}).deep_dup
          metadata[Config::ACCOUNT_KEY] = {
            'source' => 'manual',
            'synced_at' => nil,
            'methods' => normalized['methods'],
            'currencies' => normalized['currencies'],
            'countries' => normalized['countries'],
            'updated_at' => now.utc.iso8601,
            'updated_by' => actor.presence
          }.compact

          payment_method.update_columns(private_metadata: metadata)
          true
        end

        def result(payment_method, normalized, rejected, unchanged:)
          payment_method.reload if unchanged == false

          {
            'ok' => true,
            'unchanged' => unchanged,
            'account' => Config.account_config(payment_method),
            'normalized' => normalized,
            'rejected' => rejected.compact
          }
        end
      end
    end
  end
end
