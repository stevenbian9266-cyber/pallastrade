# frozen_string_literal: true

# PALLAS-CUSTOM: D8（PRD-20260915-payments-d8 切片1）—— 规则求值器（纯函数，无 DB 写入）。
#
# 语义（业务方案 §66.2）：
#   - exclude 命中即不可用（**否定优先**，无论 include 是否命中）；
#   - include 为空 = 不限；match: all（默认）要求全部命中；match: any 至少一条命中；
#   - 未知上下文（如地址未填的 country/zone）→ 条件视为**未命中**：
#       include 侧 = fail closed（不承诺未知场景的可用性）；
#       exclude 侧 = fail open（排除必须有正证据，避免误隐藏）。
#
# @return [Hash] { 'allowed' => Boolean, 'reasons' => [ { 'dimension' =>, 'operator' =>,
#                  'values' =>, 'observed' =>, 'outcome' => 'excluded'|'not_matched' } ] }
module PallasTrade
  module Payments
    module Availability
      module Evaluator
        ALLOWED_RESULT = { 'allowed' => true, 'reasons' => [] }.freeze

        module_function

        def evaluate(rule_set, context)
          return ALLOWED_RESULT if rule_set.blank?

          excluded = rule_set['exclude'].select { |condition| condition_hit?(condition, context) }
          if excluded.any?
            return {
              'allowed' => false,
              'reasons' => excluded.map { |condition| reason(condition, context, 'excluded') }
            }
          end

          includes = rule_set['include']
          return ALLOWED_RESULT if includes.empty?

          hits = includes.select { |condition| condition_hit?(condition, context) }
          enough = rule_set['match'] == 'any' ? hits.any? : hits.size == includes.size
          return ALLOWED_RESULT if enough

          unmet = includes.reject { |condition| condition_hit?(condition, context) }
          { 'allowed' => false, 'reasons' => unmet.map { |condition| reason(condition, context, 'not_matched') } }
        end

        def allowed?(rule_set, context)
          evaluate(rule_set, context)['allowed']
        end

        # 条件是否命中；未知上下文（observed 为空）一律不命中。
        def condition_hit?(condition, context)
          observed = observed_values(condition['dimension'], context)
          return false if observed.empty?

          if condition['operator'] == 'not_in'
            (condition['values'] & observed).empty?
          else
            (condition['values'] & observed).any?
          end
        end

        def reason(condition, context, outcome)
          {
            'dimension' => condition['dimension'],
            'operator' => condition['operator'],
            'values' => condition['values'],
            'observed' => observed_values(condition['dimension'], context),
            'outcome' => outcome
          }
        end

        def observed_values(dimension, context)
          case dimension
          when 'market' then Array(context.market_id)
          when 'country' then Array(context.country_iso)
          when 'zone' then Array(context.zone_ids)
          when 'currency' then Array(context.currency)
          else []
          end
        end
      end
    end
  end
end
