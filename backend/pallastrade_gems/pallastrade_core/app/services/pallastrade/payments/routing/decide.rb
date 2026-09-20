# frozen_string_literal: true

# PALLAS-CUSTOM: PAY-CORE-P3A（PRD-20260920-checkout 支付核心统一 · 切片 P3-A）——
# **方式级路由决策**（业务方案 §2.4）：一个「支付方式」在某个订单上下文里由**哪家厂商**承接。
#
# 决策链（硬门 → 排序，全部复用既有权威，不复制判定）：
#   1. 硬门：该厂商是否配置了该方式（入口存在且启用）
#   2. 硬门：厂商三态（P0：`Providers::State` —— disabled / suspended 直接出局）
#   3. 硬门：账户收窄（P0-B：`Providers::Config.effective` —— 账户未开通的方式出局）
#   4. 硬门：**`Availability::Resolver`**（D8 范围规则 / D11 熔断 / D15c 认证闸门 / 能力目录 —— 与前台同一求值点）
#   5. 排序：策略优先序（市场覆写 > 全局）→ 入口 `position` → `provider.prefixed_id`（确定性兜底）
#
# 铁律：
#   - **离线/纯读**：零写入、零网络、零资金副作用（决策对象为 transient Hash，留痕由调用方负责）；
#   - **不猜**：候选为空即 `no_candidate`，不回落"默认厂商"；未实现的成本/健康维度不参与排序；
#   - **确定性**：同一输入 + 同一策略 ⇒ 同一结果（同分按 `position` 与 provider id 兜底）。
module PallasTrade
  module Payments
    module Routing
      module Decide
        POLICY_VERSION = 'v1'
        STATUS_DECIDED = 'decided'
        STATUS_NO_CANDIDATE = 'no_candidate'

        module_function

        # @param order [PallasTrade::Order]
        # @param method_key [String] 前台支付方式（card / apple_pay / …）
        # @param policy [Hash, nil] 已归一策略（缺省从 store 读）
        # @return [Hash] 决策对象（见下面的键说明）
        def call(order:, method_key:, policy: nil)
          method_key = method_key.to_s
          store = order.store
          policy ||= Policy.for_store(store)
          context = Availability::Context.for_order(order)

          candidates = []
          rejected = []

          Array(store.payment_methods).each do |payment_method|
            option = option_for(payment_method, method_key)
            if option.nil?
              rejected << rejection(payment_method, 'method_not_configured')
              next
            end

            state = Providers::State.state(payment_method)
            if state != Providers::State::ENABLED
              rejected << rejection(payment_method, "provider_#{state}")
              next
            end

            unless account_allows?(payment_method, method_key)
              rejected << rejection(payment_method, 'account_not_opened')
              next
            end

            unless available_for_order?(order, payment_method, method_key, context)
              rejected << rejection(payment_method, 'not_available_for_order')
              next
            end

            candidates << candidate(payment_method, option, method_key)
          end

          ranked = rank(candidates, policy: policy, method_key: method_key, market_id: context.market_id)
          chosen = ranked.first

          {
            'method_key' => method_key,
            'mode' => policy['mode'],
            'applied' => Policy.applied?(policy),
            'unsupported_mode' => policy['unsupported_mode'],
            'policy_version' => POLICY_VERSION,
            'status' => chosen ? STATUS_DECIDED : STATUS_NO_CANDIDATE,
            'basis' => chosen&.[]('basis'),
            'chosen' => chosen,
            'candidates' => ranked,
            'rejected' => rejected,
            'inputs' => {
              'store_id' => store.prefixed_id,
              'order_id' => order.prefixed_id,
              'market_id' => context.market_id,
              'currency' => context.currency
            }
          }
        end

        # 已配置且启用的入口（选项化 → 配置入口；未选项化 → 隐式默认入口）。
        def option_for(payment_method, method_key)
          if payment_method.optionized?
            Array(payment_method.payment_options).find do |option|
              option['kind'].to_s == method_key && option['active'] != false
            end
          elsif payment_method.default_option_kind.to_s == method_key
            payment_method.default_payment_option
          end
        end

        # 账户收窄：声明了账户方式清单时，只有其中列出的方式可用（未声明 = 不收窄，不猜）。
        def account_allows?(payment_method, method_key)
          allowed = Providers::Config.effective(payment_method)['methods']['values']
          allowed.nil? || allowed.include?(method_key)
        end

        # 复用前台求值点（D8 规则 / D11 熔断 / D15c 认证 / 能力目录）—— 保证「路由选中的」= 「前台能付的」。
        def available_for_order?(order, payment_method, method_key, context)
          return true unless defined?(Availability::Resolver)

          Availability::Resolver.option_available?(
            order: order, payment_method: payment_method, kind: method_key, context: context
          )
        rescue StandardError
          false
        end

        def candidate(payment_method, option, method_key)
          {
            'provider_id' => payment_method.prefixed_id,
            'provider_name' => payment_method.name,
            'option_id' => payment_method.option_identifier(method_key),
            'display_name' => payment_method.option_display_name(method_key),
            'position' => option['position'].to_i,
            'method_key' => method_key
          }
        end

        def rejection(payment_method, reason)
          { 'provider_id' => payment_method.prefixed_id, 'provider_name' => payment_method.name, 'reason' => reason }
        end

        # 排序：优先序（指定者在前，按给定顺序）→ 入口 position → provider id（确定性兜底）。
        def rank(candidates, policy:, method_key:, market_id:)
          sequence = Policy.priority_sequence(policy, method_key: method_key, market_id: market_id)

          candidates.sort_by do |item|
            index = sequence.index(item['provider_id'])
            [
              index.nil? ? 1 : 0,
              (index || 0) + (index.nil? ? 1_000 : 0),
              item['position'],
              item['provider_id']
            ]
          end.each_with_index.map do |item, position|
            item.merge(
              'rank' => position + 1,
              'basis' => sequence.include?(item['provider_id']) ? 'priority_override' : 'position'
            )
          end
        end
      end
    end
  end
end
