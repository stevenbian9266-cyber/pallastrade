# frozen_string_literal: true

# PALLAS-CUSTOM: PAY-CORE-P3B（PRD-20260920-checkout 支付核心统一 · 切片 P3-B）——
# **无订单上下文**的路由预览（「顾客会看到什么 / 会走哪家」）。
#
# 与 `Decide` 的关系：复用其候选装配与排序（`option_for` / `account_allows?` / `candidate` / `rank`），
# **唯一区别是跳过订单级闸门**（D8 范围规则 / D11 熔断 / D15c 认证 —— 这些需要订单上下文）。
# 因此结果标记 `order_gates: 'skipped'` + `status: 'preview'`：**不假装是完整决策**，
# 只回答「按当前策略与厂商/账户状态，谁排在前面」。
#
# 铁律：纯读（零写入、零网络、零资金副作用）；无候选 → 该方式不出现在结果里（不猜）。
module PallasTrade
  module Payments
    module Routing
      module Summary
        ORDER_GATES_SKIPPED = 'skipped'
        STATUS_PREVIEW = 'preview'

        module_function

        # @param store [PallasTrade::Store]
        # @param market_id [String, Integer, nil] 市场（用于市场覆写；缺省不套用覆写）
        # @return [Hash] { 'mode', 'applied', 'unsupported_mode', 'order_gates', 'methods' => { <kind> => {...} } }
        def for_store(store, market_id: nil, policy: nil)
          policy ||= Policy.for_store(store)
          providers = Array(store.payment_methods)

          {
            'mode' => policy['mode'],
            'applied' => Policy.applied?(policy),
            'unsupported_mode' => policy['unsupported_mode'],
            'order_gates' => ORDER_GATES_SKIPPED,
            'methods' => method_keys(providers).to_h do |method_key|
              [method_key, preview(providers, method_key, policy: policy, market_id: market_id)]
            end
          }
        end

        # 该店所有 provider 声称支持的方式（选项化 → 配置入口；未选项化 → 隐式默认入口）。
        def method_keys(providers)
          providers.flat_map do |payment_method|
            if payment_method.optionized?
              Array(payment_method.payment_options)
                .select { |option| option['active'] != false }
                .map { |option| option['kind'].to_s }
            else
              [payment_method.default_option_kind.to_s]
            end
          end.reject(&:blank?).uniq.sort
        end

        def preview(providers, method_key, policy:, market_id: nil)
          candidates = []
          rejected = []

          providers.each do |payment_method|
            option = Decide.option_for(payment_method, method_key)
            if option.nil?
              next # 该 provider 不支持此方式：不需要逐条 reason（预览不是排查面）
            end

            state = Providers::State.state(payment_method)
            if state != Providers::State::ENABLED
              rejected << Decide.rejection(payment_method, "provider_#{state}")
              next
            end

            unless Decide.account_allows?(payment_method, method_key)
              rejected << Decide.rejection(payment_method, 'account_not_opened')
              next
            end

            candidates << Decide.candidate(payment_method, option, method_key)
          end

          ranked = Decide.rank(candidates, policy: policy, method_key: method_key, market_id: market_id)
          chosen = ranked.first

          {
            'status' => chosen ? STATUS_PREVIEW : 'no_candidate',
            'basis' => chosen&.[]('basis'),
            'chosen' => chosen,
            'candidates' => ranked,
            'rejected' => rejected
          }
        end
      end
    end
  end
end
