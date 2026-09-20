# frozen_string_literal: true

# PALLAS-CUSTOM: PAY-CORE-P3A（PRD-20260920-checkout 支付核心统一 · 切片 P3-A）——
# 方式级路由**策略**读取（业务方案 §2.4）：策略存 `store.private_metadata['payment_routing']`（零迁移）。
#
#   {
#     "mode": "off" | "shadow" | "priority_only",
#     "priority": { "card": ["pm_aaa", "pm_bbb"] },          # 方式 → provider 优先序（prefixed_id）
#     "markets":  { "mkt_1": { "card": ["pm_bbb"] } }        # 市场覆写（同结构，市场优先）
#   }
#
# 诚实性约定：
#   - 尚未实现的模式（`priority_cost` / `priority_cost_health` 等）→ 归一为 `off` 并标 `unsupported_mode`，
#     绝不"装作在按成本排"（成本不可判定时不猜）；
#   - 非法结构一律忽略（不 raise）；缺省 `off` = **零行为变化**。
module PallasTrade
  module Payments
    module Routing
      module Policy
        KEY = 'payment_routing'
        MODES = %w[off shadow priority_only].freeze
        DEFAULT_MODE = 'off'
        MAX_SEQUENCE = 50

        module_function

        def for_store(store)
          raw = store.respond_to?(:private_metadata) ? store.private_metadata&.[](KEY) : nil
          normalize(raw)
        end

        # @return [Hash] { 'mode', 'unsupported_mode', 'priority', 'markets' }
        def normalize(raw)
          return default_policy unless raw.respond_to?(:[])

          submitted = fetch(raw, 'mode').to_s.downcase
          unsupported = submitted.present? && !MODES.include?(submitted)

          {
            'mode' => MODES.include?(submitted) ? submitted : DEFAULT_MODE,
            'unsupported_mode' => unsupported,
            'priority' => normalize_priority(fetch(raw, 'priority')),
            'markets' => normalize_markets(fetch(raw, 'markets'))
          }
        end

        def default_policy
          { 'mode' => DEFAULT_MODE, 'unsupported_mode' => false, 'priority' => {}, 'markets' => {} }
        end

        def applied?(policy)
          policy['mode'] == 'priority_only'
        end

        # 生效优先序：市场覆写优先于全局；两者都没有 → 空数组（= 按入口 position 排）。
        def priority_sequence(policy, method_key:, market_id: nil)
          key = method_key.to_s
          scoped = market_id.present? ? policy['markets'][market_id.to_s] : nil

          (scoped&.[](key) || policy['priority'][key] || []).dup
        end

        def normalize_priority(raw)
          return {} unless raw.respond_to?(:each_pair)

          raw.each_pair.with_object({}) do |(key, value), accumulator|
            sequence = normalize_sequence(value)
            accumulator[key.to_s] = sequence if sequence.any?
          end
        end

        def normalize_markets(raw)
          return {} unless raw.respond_to?(:each_pair)

          raw.each_pair.with_object({}) do |(key, value), accumulator|
            accumulator[key.to_s] = normalize_priority(value)
          end
        end

        def normalize_sequence(raw)
          Array(raw).first(MAX_SEQUENCE).map { |value| value.to_s.strip }.reject(&:blank?).uniq
        end

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
