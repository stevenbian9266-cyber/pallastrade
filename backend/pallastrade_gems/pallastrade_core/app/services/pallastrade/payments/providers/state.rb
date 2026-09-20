# frozen_string_literal: true

# PALLAS-CUSTOM: PAY-CORE-P0A（PRD-20260920-checkout 支付核心统一 · 切片 P0-A）——
# 厂商**三态**唯一读取口径 + 写入原语（业务方案 §2.1）。
#
#   enabled   —— 人工启用（`active = true`）且没有被熔断
#   disabled  —— 人工停用（`active = false`）：**粘性**，`resume!` 不会自动恢复
#   suspended —— 熔断（D11 `soft_disable!`；含 `manual: true` 的人工粘性熔断）
#
# 判定优先级：`disabled` > `suspended` > `enabled`（人工停用是绝对态）。
# 铁律：**零资金副作用** —— 本模块只改 `active` 列与 `metadata['breaker']`，
# 不触碰 Payment / PaymentSession / 账本，也不发任何 provider 请求。
module PallasTrade
  module Payments
    module Providers
      module State
        ENABLED = 'enabled'
        DISABLED = 'disabled'
        SUSPENDED = 'suspended'
        STATES = [ENABLED, DISABLED, SUSPENDED].freeze

        module_function

        # @return [String] enabled / disabled / suspended
        def state(payment_method)
          return DISABLED if disabled?(payment_method)
          return SUSPENDED if suspended?(payment_method)

          ENABLED
        end

        def disabled?(payment_method)
          !payment_method.active?
        end

        # 全部生效入口均被软置灰（熔断）→ 厂商整体挂起；**部分**置灰不算整体挂起
        # （部分挂起的入口由 `Availability::Resolver` 在前台逐入口过滤）。
        def suspended?(payment_method, now: Time.current)
          kinds = effective_kinds(payment_method)
          return false if kinds.empty?

          kinds.all? { |kind| payment_method.soft_disabled?(kind, now: now) }
        end

        # 已挂起的入口清单（后台诊断卡展示部分挂起用）。
        # @return [Array<String>]
        def suspended_kinds(payment_method, now: Time.current)
          effective_kinds(payment_method).select { |kind| payment_method.soft_disabled?(kind, now: now) }
        end

        # 人工停用（粘性）。
        # @return [Boolean] 是否发生变化
        def disable!(payment_method)
          return false if disabled?(payment_method)

          payment_method.update_columns(active: false)
          true
        end

        # 人工启用（唯一的"从停用恢复"入口 —— 必须人工调用）。
        # @return [Boolean]
        def enable!(payment_method)
          return false if payment_method.active?

          payment_method.update_columns(active: true)
          true
        end

        # 熔断（半自动）；`manual: true` 为人工粘性熔断，只能人工 `resume!`。
        # @return [Boolean]
        def suspend!(payment_method, reason:, kind: nil, until_at: nil, manual: false, failure_rate: nil, sample_size: nil)
          payment_method.soft_disable!(
            kind: kind, reason: reason, manual: manual, until_at: until_at,
            failure_rate: failure_rate, sample_size: sample_size
          )
        end

        # 解除熔断。⚠️ **只清 breaker，绝不改 `active`**：
        # `disable!` 后调用 `resume!` 仍然是 `disabled`（人工停用必须人工解除）。
        # @return [Boolean]
        def resume!(payment_method, kind: nil)
          payment_method.soft_enable!(kind)
        end

        # 生效入口 kind 列表（已选项化 → 配置入口；未选项化 → 隐式默认入口）。
        # @return [Array<String>]
        def effective_kinds(payment_method)
          Array(payment_method.effective_payment_options).
            map { |option| option['kind'].to_s }.
            reject(&:blank?)
        end
      end
    end
  end
end
