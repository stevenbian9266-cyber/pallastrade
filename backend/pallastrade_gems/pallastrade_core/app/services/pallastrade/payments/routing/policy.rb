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

        # ------------------------------------------------------------------ 写入（P3-B）

        # 策略写入原语（业务方案 §2.4）：白名单化写入 `store.private_metadata['payment_routing']`。
        #
        # 白名单（越界值进 `rejected` 并忽略，**不 raise**）：
        #   mode     ∈ MODES（未实现模式不算合法写入值 —— 要先归一成 off 才能落库）
        #   priority 的目标厂商 ∈ 本店 provider（prefixed_id）
        #   markets  的市场键 ∈ 本店 market
        #
        # 语义：同值重复写入 → `unchanged` = true（**不写库、不审计**）；只写 store metadata，
        # 不触碰 Payment / PaymentSession / 账本（零资金副作用）。
        # @return [Hash] { 'ok', 'unchanged', 'policy', 'rejected' }
        def write!(store, mode: nil, priority: nil, markets: nil, actor: nil, now: Time.current)
          allowed = allowed_targets(store)
          rejected = {}

          submitted_mode = mode.to_s.downcase
          if submitted_mode.present? && !MODES.include?(submitted_mode)
            rejected['mode'] = [submitted_mode]
            submitted_mode = nil
          end

          current = for_store(store)
          candidate = normalize(
            'mode' => submitted_mode.presence || current['mode'],
            'priority' => filter_priority(priority, allowed['providers'], rejected),
            'markets' => filter_markets(markets, allowed['markets'], allowed['providers'], rejected)
          )

          comparable = ->(policy) { policy.slice('mode', 'priority', 'markets') }
          return result(store, candidate, rejected, unchanged: true) if comparable.call(candidate) == comparable.call(current)

          persist!(store, candidate, actor: actor, now: now)
          result(store, candidate, rejected, unchanged: false)
        end

        # 可选目标（后台表单与白名单同源）。
        def allowed_targets(store)
          {
            'providers' => Array(store.respond_to?(:payment_methods) ? store.payment_methods : [])
                            .map { |payment_method| payment_method.prefixed_id },
            'markets' => Array(store.respond_to?(:markets) ? store.markets : []).map { |market| market.id.to_s }
          }
        end

        def persist!(store, policy, actor: nil, now: Time.current)
          metadata = (store.private_metadata || {}).deep_dup
          metadata[KEY] = {
            'mode' => policy['mode'],
            'priority' => policy['priority'],
            'markets' => policy['markets'],
            'updated_at' => now.utc.iso8601,
            'updated_by' => actor.presence
          }.compact

          store.update_columns(private_metadata: metadata)
          true
        end

        def result(store, policy, rejected, unchanged:)
          store.reload if unchanged == false

          {
            'ok' => true,
            'unchanged' => unchanged,
            'policy' => for_store(store),
            'rejected' => rejected.compact
          }
        end

        def filter_priority(raw, provider_ids, rejected)
          return nil unless raw.respond_to?(:each_pair)

          raw.each_pair.with_object({}) do |(key, value), accumulator|
            sequence = normalize_sequence(value)
            keep, drop = sequence.partition { |id| provider_ids.include?(id) }
            rejected['priority'] ||= {}
            rejected['priority'][key.to_s] = drop if drop.any?
            accumulator[key.to_s] = keep if keep.any?
          end
        end

        def filter_markets(raw, market_ids, provider_ids, rejected)
          return nil unless raw.respond_to?(:each_pair)

          raw.each_pair.with_object({}) do |(key, value), accumulator|
            unless market_ids.include?(key.to_s)
              (rejected['markets'] ||= []) << key.to_s
              next
            end

            nested = filter_priority(value, provider_ids, rejected)
            accumulator[key.to_s] = nested if nested.present?
          end
        end
      end
    end
  end
end
