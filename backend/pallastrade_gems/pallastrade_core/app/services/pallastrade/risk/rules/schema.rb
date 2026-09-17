# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片2（PRD-20260917-payments-d15b-risk-rules；业务方案 §72.2）——
# `Risk::Rules::Schema` —— **规则定义的服务端强校验与归一**（发布前唯一闸门）。
#
# 为什么必须有它：规则以 JSON 落库（结构化编辑），**未知键/类型错/非法动作**若被静默接受，
# 运行期就会变成「看着生效、实际永不命中」的幽灵规则。因此：
#   * 未知条件键 → **拒绝发布**（不是静默忽略）；
#   * 类型/取值范围错 → 拒绝（金额非数字、数组超长、percent 越界…）；
#   * 归一（大写/小写/去空白/默认优先级）在**这里一次做完**，运行期不再变形。
#
# 返回：success(归一后的规则数组) / failure(错误列表, 错误文本)
module PallasTrade
  module Risk
    module Rules
      class Schema
        prepend PallasTrade::ServiceModule::Base

        ACTIONS = PallasTrade::RiskRuleVersion::ACTIONS
        MAX_RULES = PallasTrade::RiskRuleVersion::MAX_RULES
        CODE_FORMAT = /\A[a-z0-9][a-z0-9_-]{0,63}\z/
        DEFAULT_PRIORITY = 100
        MAX_PRIORITY = 10_000
        MAX_ARRAY_ITEMS = 50
        MAX_NOTE_LENGTH = 500
        MAX_VELOCITY_WINDOW_MINUTES = Condition::MAX_VELOCITY_WINDOW_MINUTES

        ARRAY_KEYS = %w[currency_in country_in email_domain_in card_brand_in].freeze
        BOOLEAN_KEYS = %w[email_present ip_present].freeze
        NUMERIC_KEYS = %w[amount_gte amount_lte customer_orders_gte velocity_count_gte].freeze
        WINDOW_KEY = 'velocity_window_minutes'

        # @param rules [Array, String] 规则数组或 JSON 文本
        # @return [PallasTrade::ServiceModule::Result]
        def call(rules:)
          @errors = []
          list = coerce_rules(rules)
          return failure(@errors, @errors.join(' | ')) if @errors.any?

          normalized = list.each_with_index.map { |rule, index| normalize_rule(rule, index) }
          validate_count!(normalized)
          validate_unique_codes!(normalized)

          return failure(@errors, @errors.join(' | ')) if @errors.any?

          success(normalized)
        end

        private

        # 同一版本内规则码必须唯一（否则留痕无法指认「命中哪条规则」）
        def validate_unique_codes!(rules)
          duplicates = rules.map { |rule| rule['code'] }.compact.tally.select { |_code, count| count > 1 }.keys
          return if duplicates.empty?

          @errors << "duplicate rule code(s): #{duplicates.join(', ')}"
        end

        def coerce_rules(rules)
          return rules if rules.is_a?(Array)
          return [] if rules.blank?

          parsed = JSON.parse(rules.to_s)
          return parsed if parsed.is_a?(Array)

          @errors << 'rules must be a JSON array'
          []
        rescue JSON::ParserError => e
          @errors << "rules is not valid JSON: #{e.message}"
          []
        end

        def validate_count!(rules)
          @errors << "rules must contain at most #{MAX_RULES} entries" if rules.size > MAX_RULES
        end

        def normalize_rule(rule, index)
          unless rule.is_a?(Hash)
            @errors << "rules[#{index}] must be an object"
            return {}
          end

          rule = rule.to_h.stringify_keys
          {
            'code' => validate_code(rule['code'], index),
            'priority' => validate_priority(rule['priority'], index),
            'action' => validate_action(rule['action'], index),
            'conditions' => validate_conditions(rule['conditions'], index),
            'note' => normalize_note(rule['note'])
          }
        end

        def validate_code(code, index)
          value = code.to_s.strip.downcase
          if value.blank?
            @errors << "rules[#{index}].code is required"
          elsif !value.match?(CODE_FORMAT)
            @errors << "rules[#{index}].code must match #{CODE_FORMAT.source}"
          end
          value
        end

        def validate_priority(priority, index)
          return DEFAULT_PRIORITY if priority.nil?

          value = begin
            Integer(priority)
          rescue ArgumentError, TypeError
            @errors << "rules[#{index}].priority must be an integer"
            return DEFAULT_PRIORITY
          end

          unless value.between?(0, MAX_PRIORITY)
            @errors << "rules[#{index}].priority must be between 0 and #{MAX_PRIORITY}"
          end
          value
        end

        def validate_action(action, index)
          value = action.to_s.strip.downcase
          @errors << "rules[#{index}].action must be one of #{ACTIONS.join('/')}" unless ACTIONS.include?(value)
          value
        end

        def validate_conditions(conditions, index)
          unless conditions.is_a?(Hash)
            @errors << "rules[#{index}].conditions must be an object"
            return {}
          end

          conditions = conditions.to_h.stringify_keys
          @errors << "rules[#{index}].conditions must not be empty" if conditions.empty?
          return {} if conditions.empty?

          normalized = conditions.each_with_object({}) do |(key, value), memo|
            memo[key] = normalize_condition(key, value, index)
          end

          if normalized.key?(WINDOW_KEY) && !normalized.key?('velocity_count_gte')
            @errors << "rules[#{index}].conditions.#{WINDOW_KEY} requires velocity_count_gte"
          end
          normalized
        end

        def normalize_condition(key, value, index)
          label = "rules[#{index}].conditions.#{key}"

          if key == WINDOW_KEY
            return validate_integer(value, label, 1, MAX_VELOCITY_WINDOW_MINUTES)
          end

          if ARRAY_KEYS.include?(key)
            return validate_array(value, label, key)
          end

          if BOOLEAN_KEYS.include?(key)
            return value if [true, false].include?(value)

            @errors << "#{label} must be true or false"
            return false
          end

          if NUMERIC_KEYS.include?(key)
            return validate_number(value, label)
          end

          @errors << "#{label} is not a supported condition (supported: #{(Condition::SUPPORTED_KEYS - [WINDOW_KEY]).join(', ')})"
          value
        end

        def validate_array(value, label, key)
          unless value.is_a?(Array)
            @errors << "#{label} must be an array"
            return []
          end

          items = value.map { |item| item.to_s.strip }.reject(&:blank?)
          if items.empty?
            @errors << "#{label} must not be empty"
          elsif items.size > MAX_ARRAY_ITEMS
            @errors << "#{label} must contain at most #{MAX_ARRAY_ITEMS} items"
          end

          case key
          when 'currency_in', 'country_in' then items.map(&:upcase)
          else items.map(&:downcase)
          end
        end

        def validate_number(value, label)
          number = begin
            BigDecimal(value.to_s)
          rescue ArgumentError, TypeError
            nil
          end
          if number.nil? || number.negative?
            @errors << "#{label} must be a non-negative number"
            return 0
          end

          number
        end

        def validate_integer(value, label, min, max)
          integer = begin
            Integer(value)
          rescue ArgumentError, TypeError
            nil
          end
          if integer.nil? || !integer.between?(min, max)
            @errors << "#{label} must be an integer between #{min} and #{max}"
            return min
          end

          integer
        end

        def normalize_note(note)
          value = note.to_s.strip
          @errors << "note must be at most #{MAX_NOTE_LENGTH} characters" if value.length > MAX_NOTE_LENGTH
          value.presence
        end
      end
    end
  end
end
