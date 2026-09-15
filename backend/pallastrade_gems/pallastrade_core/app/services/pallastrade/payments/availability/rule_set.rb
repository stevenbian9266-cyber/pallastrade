# frozen_string_literal: true

# PALLAS-CUSTOM: D8（PRD-20260915-payments-d8 切片1）—— 入口「适用范围」规则模型
# （业务方案 §66.2 规则语义）。
#
# 存储（过渡期，不建表）：`metadata['options'][i]['rule_set']`：
#
#   rule_set = {
#     "match"   => "all" | "any",              # 默认 all
#     "include" => [ { "dimension" => "market", "operator" => "in", "values" => ["1"] } ],
#     "exclude" => [ { "dimension" => "currency", "operator" => "in", "values" => ["USD"] } ]
#   }
#
# 归一侧（写路径与读路径共用）：
#   - 维度白名单 market / country / zone / currency（其余 10 维度见业务方案 §66.1，后续批次）；
#   - 算子白名单 in / not_in / eq（eq 仅单值）；country / currency 值统一大写；
#   - 未知维度/算子、空 values、超限条目一律**忽略**（不 raise）；无有效条件 → nil（= 不限，零回归）。
module PallasTrade
  module Payments
    module Availability
      module RuleSet
        DIMENSIONS = %w[market country zone currency].freeze
        OPERATORS = %w[in not_in eq].freeze
        MATCH_MODES = %w[all any].freeze

        MAX_CONDITIONS = 20   # 单侧（include/exclude）条件数上限
        MAX_VALUES = 200      # 单条件取值数上限

        module_function

        # @param raw [Hash, ActionController::Parameters, nil]
        # @return [Hash, nil] 归一后的规则（string keys）；无有效条件返回 nil
        def normalize(raw)
          return nil unless raw.respond_to?(:[])

          match = fetch(raw, 'match').to_s
          match = 'all' unless MATCH_MODES.include?(match)

          includes = normalize_conditions(fetch(raw, 'include'))
          excludes = normalize_conditions(fetch(raw, 'exclude'))
          return nil if includes.empty? && excludes.empty?

          { 'match' => match, 'include' => includes, 'exclude' => excludes }
        end

        # 后台摘要（可传入 labels 解析器：dimension → value → 展示名）。
        # @return [String] 如 "Markets: EU · Currencies: EUR"；无规则 → 全部可用文案
        def summary(raw, labels: nil)
          rule_set = normalize(raw)
          return all_label if rule_set.blank?

          parts = []
          %w[include exclude].each do |side|
            Array(rule_set[side]).each do |condition|
              values = condition['values'].map { |value| label_for(condition['dimension'], value, labels) }
              prefix = side == 'exclude' ? "#{exclude_label} " : ''
              parts << "#{prefix}#{dimension_name(condition['dimension'])}: #{values.join(', ')}"
            end
          end
          parts.uniq.join(' · ')
        end

        # @return [String] 维度展示名（i18n，缺省回退枚举值）
        def dimension_name(dimension)
          I18n.t("pallastrade.payment_option_dimensions.#{dimension}", default: dimension.to_s.capitalize)
        end

        def all_label
          I18n.t('pallastrade.payment_option_scope_all', default: 'All')
        end

        def exclude_label
          I18n.t('pallastrade.payment_option_scope_exclude', default: 'Exclude')
        end

        def label_for(dimension, value, labels)
          return value unless labels.respond_to?(:call)

          labels.call(dimension, value).presence || value
        end

        def normalize_conditions(list)
          Array(list).first(MAX_CONDITIONS).filter_map { |entry| normalize_condition(entry) }
        end

        def normalize_condition(entry)
          return nil unless entry.respond_to?(:[])

          dimension = fetch(entry, 'dimension').to_s
          operator = fetch(entry, 'operator').to_s
          operator = 'in' if operator.blank?
          values = normalize_values(fetch(entry, 'values'), dimension)

          return nil unless DIMENSIONS.include?(dimension) && OPERATORS.include?(operator)
          return nil if values.empty?
          return nil if operator == 'eq' && values.size != 1

          { 'dimension' => dimension, 'operator' => operator, 'values' => values }
        end

        def normalize_values(raw, dimension)
          values = Array(raw).map { |value| value.to_s.strip }.reject(&:blank?).uniq.first(MAX_VALUES)
          %w[country currency].include?(dimension) ? values.map(&:upcase) : values
        end

        # 兼容 string / symbol 键（Hash、HashWithIndifferentAccess、Parameters）。
        # 非 Hash 类容器（String / Array 等脏数据）一律当缺失处理。
        def fetch(container, key)
          return nil unless container.respond_to?(:[])
          return nil if container.is_a?(String) || container.is_a?(Array)

          value = container[key]
          value.nil? ? container[key.to_sym] : value
        end
      end
    end
  end
end
