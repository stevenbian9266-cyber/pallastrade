# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片3（PRD-20260917-checkout-d15-切片3；业务方案 §72.1 / §78-D15）——
# `Payments::ThreeDSecure::Policy` —— 门店 3DS/SCA 策略的**唯一读/写口径**。
#
# 存储：`store.private_metadata['three_d_secure_policy']`（与 `dispute_rate_policy` 同先例，**零迁移**）。
# 模式（业务方案 §72.1）：
#   * `always`     —— 全部挑战（高风险市场 / 过渡期）；
#   * `risk_based` —— **默认**：仅高风险（规则 `force_3ds`）挑战，其余走豁免；
#   * `off`        —— 不挑战（仅在非 PSD2 地区、且已确认合规前提下使用）。
# 豁免（同样来自 §72.1）：低金额（TRA）、国家白名单、入口白名单。
#
# 两条路径，语义不同，不得混用：
#   * `normalize`（**读**路径）：永不抛错。非法值 → 回落默认 + 记 `reasons`（读侧 fail safe，
#     绝不因为运营写坏了一个键就让结账 500）；
#   * `storable`（**写**路径）：后台表单校验。非法值 → `errors`，**不落库**。
#
# 铁律：本类零 provider、零写库、零资金副作用；只做归一化与解释。
module PallasTrade
  module Payments
    module ThreeDSecure
      class Policy
        MODES = %w[always risk_based off].freeze
        DEFAULT_MODE = 'risk_based'
        STORE_METADATA_KEY = 'three_d_secure_policy'
        MAX_ALLOWLIST_ENTRIES = 100

        attr_reader :mode, :low_amount_threshold, :allowlisted_countries, :allowlisted_option_kinds, :reasons

        def initialize(mode: DEFAULT_MODE, low_amount_threshold: nil, allowlisted_countries: [],
                       allowlisted_option_kinds: [], reasons: [])
          @mode = mode
          @low_amount_threshold = low_amount_threshold
          @allowlisted_countries = allowlisted_countries
          @allowlisted_option_kinds = allowlisted_option_kinds
          @reasons = reasons
        end

        # @param store [PallasTrade::Store, nil]
        # @return [Policy]
        def self.for(store)
          raw = store.respond_to?(:private_metadata) ? store.private_metadata.to_h[STORE_METADATA_KEY] : nil
          normalize(raw)
        end

        # 读路径归一化：非法值回落默认并记 reasons（永不抛错）
        # @param raw [Hash, String, nil]
        # @return [Policy]
        def self.normalize(raw)
          source = coerce_hash(raw)
          reasons = []

          mode = source['mode'].to_s.strip.downcase
          if mode.blank?
            mode = DEFAULT_MODE
          elsif !MODES.include?(mode)
            reasons << "unknown_mode:#{mode}"
            mode = DEFAULT_MODE
          end

          threshold, threshold_reason = normalize_threshold(source['low_amount_threshold'])
          reasons << threshold_reason if threshold_reason.present?

          countries = normalize_countries(source['allowlisted_countries'], reasons)
          kinds = normalize_option_kinds(source['allowlisted_option_kinds'])

          new(mode: mode, low_amount_threshold: threshold, allowlisted_countries: countries,
              allowlisted_option_kinds: kinds, reasons: reasons)
        end

        # 写路径校验（后台表单）：非法值 → errors，不落库
        # @return [Array(Hash, Array<String>)] [attributes, errors]
        def self.storable(raw)
          source = coerce_hash(raw)
          errors = []

          mode = source['mode'].to_s.strip.downcase
          mode = DEFAULT_MODE if mode.blank?
          errors << "unknown_mode:#{mode}" unless MODES.include?(mode)

          threshold, threshold_reason = normalize_threshold(source['low_amount_threshold'])
          errors << threshold_reason if threshold_reason.present?

          countries = []
          Array(source['allowlisted_countries']).flat_map { |value| value.to_s.split(',') }.each do |value|
            code = value.to_s.strip.upcase
            next if code.blank?

            if code.match?(/\A[A-Z]{2}\z/)
              countries << code
            else
              errors << "invalid_country:#{code}"
            end
          end

          kinds = normalize_option_kinds(source['allowlisted_option_kinds'])

          attributes = {
            'mode' => MODES.include?(mode) ? mode : DEFAULT_MODE,
            'low_amount_threshold' => threshold&.to_s('F'),
            'allowlisted_countries' => countries.uniq.first(MAX_ALLOWLIST_ENTRIES),
            'allowlisted_option_kinds' => kinds
          }
          [attributes, errors.uniq]
        end

        # 是否「未配置」（元数据无该键）——用于后台展示与零感回归说明
        def self.configured_for?(store)
          store.respond_to?(:private_metadata) &&
            store.private_metadata.to_h.key?(STORE_METADATA_KEY)
        end

        def to_h
          {
            'mode' => mode,
            'low_amount_threshold' => low_amount_threshold&.to_s('F'),
            'allowlisted_countries' => allowlisted_countries,
            'allowlisted_option_kinds' => allowlisted_option_kinds
          }
        end

        def always? = mode == 'always'
        def risk_based? = mode == 'risk_based'
        def off? = mode == 'off'

        # 是否配置了任何放宽项（供判定服务解释）
        def exemptions_configured?
          low_amount_threshold.present? || allowlisted_countries.any? || allowlisted_option_kinds.any?
        end

        class << self
          private

          def coerce_hash(raw)
            case raw
            when nil then {}
            when Hash then raw.stringify_keys
            when String
              parsed = begin
                JSON.parse(raw)
              rescue JSON::ParserError
                nil
              end
              parsed.is_a?(Hash) ? parsed.stringify_keys : {}
            else
              raw.respond_to?(:to_h) ? raw.to_h.stringify_keys : {}
            end
          end

          # 阈值：正数才有效。**不跨币种猜**的语义由判定服务承担，这里只管数值。
          def normalize_threshold(raw)
            return [nil, nil] if raw.nil? || raw.to_s.strip.blank?

            decimal = begin
              BigDecimal(raw.to_s.strip)
            rescue ArgumentError, TypeError
              nil
            end
            return [nil, 'invalid_threshold'] if decimal.nil? || decimal <= 0

            [decimal, nil]
          end

          def normalize_countries(raw, reasons)
            list = case raw
                   when nil then []
                   when Array then raw
                   else raw.to_s.split(',')
                   end

            codes = []
            list.each do |value|
              code = value.to_s.strip.upcase
              next if code.blank?

              if code.match?(/\A[A-Z]{2}\z/)
                codes << code
              else
                reasons << "invalid_country:#{code}"
              end
            end
            codes.uniq.first(MAX_ALLOWLIST_ENTRIES)
          end

          def normalize_option_kinds(raw)
            list = case raw
                   when nil then []
                   when Array then raw
                   else raw.to_s.split(',')
                   end
            list.map { |value| value.to_s.strip.downcase }.reject(&:blank?).uniq.first(MAX_ALLOWLIST_ENTRIES)
          end
        end
      end
    end
  end
end
