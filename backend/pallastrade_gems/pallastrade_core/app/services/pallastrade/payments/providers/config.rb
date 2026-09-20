# frozen_string_literal: true

# PALLAS-CUSTOM: PAY-CORE-P0A（PRD-20260920-checkout 支付核心统一 · 切片 P0-A）——
# 「厂商层」配置读模型：厂商能力声明 / 账户配置 / 收窄（业务方案 §2.2 / §2.3）。
#
# 厂商（provider）在本仓 = 一条 `PallasTrade::PaymentMethod` 记录（STI `type` = 网关类），
# 因此**不新建厂商表**，配置沿用 `metadata`（与 D8/D9/D11/D16 同范式，零迁移）：
#
#   metadata['account'] = {
#     "source"     => "manual" | "synced",     # 账户配置来源（synced = 从 PSP 同步）
#     "synced_at"  => "2026-09-20T10:00:00Z",
#     "methods"    => ["card", "apple_pay"],   # 账户已开通的支付方式
#     "currencies" => ["USD", "EUR"],
#     "countries"  => ["US", "DE"]
#   }
#
# 归一原则（与 `Availability::RuleSet` 同口径）：
#   - 未知键 / 非法结构一律**忽略**（不 raise），保证读路径安全；
#   - `nil` = **未声明**（不猜，不做该维度收窄）；`[]` = 明确"没有任何"（收窄到空）；
#   - 本模块**只读**（零写入、零网络、零资金副作用）。
module PallasTrade
  module Payments
    module Providers
      module Config
        ACCOUNT_KEY = 'account'
        ACCOUNT_SOURCES = %w[manual synced].freeze
        MAX_LIST = 200
        SCOPE_DIMENSIONS = %w[market country currency zone].freeze

        # 能力声明的「已解释」键；其余声明键（幂等 / 退款 / 争议 / 结算 / 3DS…）原样透传到
        # `traits` —— 避免声明被静默丢弃（P3 路由与成本将消费这些事实）。
        KNOWN_CAPABILITY_KEYS = %w[
          methods currencies countries amount amount_min amount_max session_based
        ].freeze

        module_function

        # 厂商能力声明（静态：provider gem 声明"这家厂商支持什么"）。
        #   - provider 类定义类方法 `provider_capability`（Hash）→ 以声明为准（source = declared）；
        #   - 未声明 → 从 `payment_option_catalog` + `session_required?` 推导（source = derived）。
        # @return [Hash] { 'source', 'methods', 'method_keys', 'currencies', 'countries',
        #                  'amount_min', 'amount_max', 'session_based' }
        def capability(payment_method)
          declared = declared_capability(payment_method)
          if declared.is_a?(Hash)
            return normalize_capability(declared, 'declared',
                                        fallback_methods: derived_capability(payment_method)['methods'])
          end

          normalize_capability(derived_capability(payment_method), 'derived')
        end

        # 账户配置（这家**商家的账户**开通了什么）。缺失/非法 → source = manual 且各维度 nil（不猜）。
        # @return [Hash] { 'source', 'synced_at', 'methods', 'currencies', 'countries', 'configured' }
        def account_config(payment_method)
          raw = fetch(metadata_of(payment_method), ACCOUNT_KEY)
          return empty_account_config unless raw.respond_to?(:[])

          source = fetch(raw, 'source').to_s
          source = 'manual' unless ACCOUNT_SOURCES.include?(source)

          methods = normalize_kind_list(fetch(raw, 'methods'))
          currencies = normalize_code_list(fetch(raw, 'currencies'))
          countries = normalize_code_list(fetch(raw, 'countries'))

          {
            'source' => source,
            'synced_at' => normalize_time(fetch(raw, 'synced_at')),
            'methods' => methods,
            'currencies' => currencies,
            'countries' => countries,
            'configured' => !(methods.nil? && currencies.nil? && countries.nil?)
          }
        end

        # 收窄（能力 ∩ 账户）。任一维度未声明 → **不收窄**（基 = 已声明的一侧），并标注依据。
        # @return [Hash] { 'values', 'narrowed' => Boolean, 'basis' }
        def narrow(capability_values, account_values)
          if capability_values.nil? && account_values.nil?
            { 'values' => nil, 'narrowed' => false, 'basis' => 'undeclared' }
          elsif account_values.nil?
            { 'values' => capability_values, 'narrowed' => false, 'basis' => 'capability' }
          elsif capability_values.nil?
            { 'values' => account_values, 'narrowed' => false, 'basis' => 'account' }
          else
            { 'values' => capability_values & account_values, 'narrowed' => true, 'basis' => 'capability+account' }
          end
        end

        # 「能力 ∩ 账户」三方收窄后的生效清单（读路径唯一口径）。
        # @return [Hash] { 'methods', 'currencies', 'countries' } —— 每项为 narrow(...) 的结构
        def effective(payment_method)
          cap = capability(payment_method)
          account = account_config(payment_method)

          {
            'methods' => narrow(cap['method_keys'], account['methods']),
            'currencies' => narrow(cap['currencies'], account['currencies']),
            'countries' => narrow(cap['countries'], account['countries'])
          }
        end

        # 已配置入口的「适用范围」（include 侧 4 维度并集；市场/Zone 为原始 id）。
        # @return [Hash] { 'market' => [...], 'country' => [...], 'currency' => [...], 'zone' => [...] }
        def configured_scope(payment_method)
          accumulator = SCOPE_DIMENSIONS.to_h { |dimension| [dimension, []] }

          options = Array(effective_payment_options(payment_method))
          options.each do |option|
            rule_set = normalize_rule_set(option['rule_set'])
            next if rule_set.blank?

            Array(rule_set['include']).each do |condition|
              dimension = condition['dimension'].to_s
              next unless accumulator.key?(dimension)

              accumulator[dimension] |= Array(condition['values']).map(&:to_s)
            end
          end

          accumulator['currency'] = accumulator['currency'].map(&:upcase)
          accumulator
        end

        # ------------------------------------------------------------------ 归一（私有实现）

        def declared_capability(payment_method)
          return nil unless payment_method.respond_to?(:provider_capability_declaration)

          payment_method.provider_capability_declaration
        end

        def derived_capability(payment_method)
          catalog = Array(payment_method.respond_to?(:payment_option_catalog) ? payment_method.payment_option_catalog : [])

          {
            'methods' => catalog,
            'currencies' => nil,
            'countries' => nil,
            'session_based' => session_based?(payment_method)
          }
        end

        # P0-B：provider 声明可以只写“稳定事实”（会话模式 / 幂等 / 退款能力…）而**省略 methods** ——
        # 此时入口集合回落能力目录推导（否则会把既有启用入口误报 `kind_not_declared`）。
        def normalize_capability(raw, source, fallback_methods: [])
          amount = fetch(raw, 'amount')
          methods = normalize_methods(fetch(raw, 'methods'))
          methods = normalize_methods(fallback_methods) if methods.empty?

          {
            'source' => source,
            'methods' => methods,
            'method_keys' => methods.map { |entry| entry['kind'] },
            'currencies' => normalize_code_list(fetch(raw, 'currencies')),
            'countries' => normalize_code_list(fetch(raw, 'countries')),
            'amount_min' => normalize_amount(fetch(raw, 'amount_min') || fetch(amount, 'min')),
            'amount_max' => normalize_amount(fetch(raw, 'amount_max') || fetch(amount, 'max')),
            'session_based' => normalize_boolean(fetch(raw, 'session_based')) || session_based?(raw),
            'traits' => declared_traits(raw)
          }
        end

        # 声明中未被框架解释的键（不删不改，原样透传；非 Hash → 空）。
        def declared_traits(raw)
          return {} unless raw.respond_to?(:each_pair)

          raw.each_pair.with_object({}) do |(key, value), accumulator|
            name = key.to_s
            accumulator[name] = value unless KNOWN_CAPABILITY_KEYS.include?(name)
          end
        end

        def normalize_methods(raw)
          Array(raw).first(MAX_LIST).filter_map do |entry|
            case entry
            when String, Symbol
              kind = entry.to_s.strip
              kind.present? ? { 'kind' => kind, 'frontend_kind' => nil, 'three_d_secure' => nil } : nil
            else
              next unless entry.respond_to?(:[])

              kind = fetch(entry, 'kind').to_s.strip
              next if kind.blank?

              {
                'kind' => kind,
                'frontend_kind' => fetch(entry, 'frontend_kind').presence&.to_s,
                'three_d_secure' => normalize_three_d_secure(fetch(entry, 'three_d_secure'))
              }
            end
          end.uniq { |entry| entry['kind'] }
        end

        # 目录/声明的 `three_d_secure` 取值：'supported' / 'unsupported'；缺失 = nil（不猜）。
        def normalize_three_d_secure(value)
          normalized = value.to_s.strip.downcase
          return nil if normalized.blank?
          return 'supported' if %w[supported yes true].include?(normalized)
          return 'unsupported' if %w[unsupported no false].include?(normalized)

          nil
        end

        # kind 列表（支付方式标识）：小写、去空白、去重；非数组 → nil（未声明）。
        def normalize_kind_list(raw)
          return nil unless raw.is_a?(Array)

          raw.first(MAX_LIST).map { |value| value.to_s.strip.downcase }.reject(&:blank?).uniq
        end

        # ISO 码列表（国家/币种）：大写、去重；非数组 → nil（未声明）。
        def normalize_code_list(raw)
          return nil unless raw.is_a?(Array)

          raw.first(MAX_LIST).map { |value| value.to_s.strip.upcase }.reject(&:blank?).uniq
        end

        def normalize_amount(value)
          return nil if value.nil? || value.to_s.strip.empty?

          decimal = BigDecimal(value.to_s)
          decimal.negative? ? nil : decimal
        rescue ArgumentError, TypeError
          nil
        end

        def normalize_boolean(value)
          return nil if value.nil?

          ActiveModel::Type::Boolean.new.cast(value)
        end

        def normalize_time(value)
          return nil if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def empty_account_config
          {
            'source' => 'manual',
            'synced_at' => nil,
            'methods' => nil,
            'currencies' => nil,
            'countries' => nil,
            'configured' => false
          }
        end

        def effective_payment_options(payment_method)
          return [] unless payment_method.respond_to?(:effective_payment_options)

          payment_method.effective_payment_options
        end

        def normalize_rule_set(raw)
          PallasTrade::Payments::Availability::RuleSet.normalize(raw)
        end

        def session_based?(payment_method)
          return normalize_boolean(fetch(payment_method, 'session_based')) unless payment_method.respond_to?(:session_required?)

          !!payment_method.session_required?
        end

        def metadata_of(payment_method)
          payment_method.respond_to?(:metadata) ? payment_method.metadata : nil
        end

        # 兼容 string / symbol 键（`metadata` 为 JSON 列，声明多为 symbol）。
        def fetch(source, key)
          return nil unless source.respond_to?(:[])

          value = source[key]
          value = source[key.to_sym] if value.nil? && key.respond_to?(:to_sym)
          value
        end
      end
    end
  end
end
