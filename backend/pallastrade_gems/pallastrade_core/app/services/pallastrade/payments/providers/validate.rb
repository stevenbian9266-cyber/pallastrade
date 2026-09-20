# frozen_string_literal: true

# PALLAS-CUSTOM: PAY-CORE-P0A（PRD-20260920-checkout 支付核心统一 · 切片 P0-A）——
# 厂商配置**收窄校验**（业务方案 §2.3）：把"前台为什么看不到 / 为什么点了不能用"变成可解释清单。
#
# 判定链：**静态能力 ∩ 账户配置 ∩ 市场范围**（逐维度收窄，任一侧未声明则该维度不收窄）。
#
# 铁律：
#   - **只读**：零写入、零网络、零资金副作用（不修配置、不阻断保存）；
#   - **不猜**：账户配置缺失 → `account_not_configured`（info），绝不回落成"全部已开通"；
#   - 诊断项 = `severity` + `code` + `kind/kinds` + `params`（文案由视图 i18n 渲染，服务不产英文文案）。
#
# 写路径行为**保持现状**（后台归一仍静默丢弃非法值）——本切片只补齐「可解释性」，
# 强制拒绝改由 P0-B 承接（避免破坏 D1/D8/D9/D11 既有 spec）。
module PallasTrade
  module Payments
    module Providers
      module Validate
        SEVERITY_ERROR = 'error'
        SEVERITY_WARNING = 'warning'
        SEVERITY_INFO = 'info'
        SEVERITIES = [SEVERITY_ERROR, SEVERITY_WARNING, SEVERITY_INFO].freeze

        module_function

        # @return [Array<Hash>] [{ 'severity', 'code', 'params' }]
        def issues(payment_method)
          cap = Config.capability(payment_method)
          account = Config.account_config(payment_method)
          effective = Config.effective(payment_method)
          enabled_kinds = enabled_option_kinds(payment_method)

          result = []
          result.concat(method_issues(payment_method, cap, account, enabled_kinds))
          result.concat(currency_issues(effective, payment_method))
          result.concat(country_issues(effective, payment_method))
          result.concat(amount_issues(cap, payment_method))
          result.concat(state_issues(payment_method, enabled_kinds))
          result
        end

        # 汇总（后台卡片 + 未来写路径门禁共用）。
        # @return [Hash] { 'ok', 'state', 'issues', 'counts' }
        def summary(payment_method)
          list = issues(payment_method)

          {
            'ok' => list.none? { |issue| issue['severity'] == SEVERITY_ERROR },
            'state' => PallasTrade::Payments::Providers::State.state(payment_method),
            'issues' => list,
            'counts' => SEVERITIES.to_h { |severity| [severity, list.count { |issue| issue['severity'] == severity }] }
          }
        end

        # ------------------------------------------------------------------ 逐维度

        # ① 启用入口必须已在**能力声明**里；② 若账户已配置，必须同时已开通。
        def method_issues(_payment_method, cap, account, enabled_kinds)
          result = []

          undeclared = enabled_kinds - cap['method_keys']
          result << issue(SEVERITY_ERROR, 'kind_not_declared', params: { 'kinds' => undeclared.join(', ') }) if undeclared.any?

          account_kinds = account['methods']
          if account_kinds.nil?
            result << issue(SEVERITY_INFO, 'account_not_configured')
          else
            not_opened = enabled_kinds - account_kinds
            result << issue(SEVERITY_WARNING, 'kind_not_in_account', params: { 'kinds' => not_opened.join(', ') }) if not_opened.any?
          end

          result
        end

        # 入口适用范围里的**币种**必须 ⊆ 能力 ∩ 账户。
        def currency_issues(effective, payment_method)
          configured = Config.configured_scope(payment_method)['currency']
          return [] if configured.empty?

          allowed = effective['currencies']['values']
          return [] if allowed.nil?

          out_of_scope = configured - allowed
          return [] if out_of_scope.empty?

          [issue(SEVERITY_WARNING, 'currency_not_available',
                 params: { 'value' => out_of_scope.join(', '), 'basis' => effective['currencies']['basis'] })]
        end

        # 入口适用范围里的**国家**必须 ⊆ 能力 ∩ 账户（市场国家继承由 D8 负责，这里只核对账户侧）。
        def country_issues(effective, payment_method)
          configured = Config.configured_scope(payment_method)['country']
          return [] if configured.empty?

          allowed = effective['countries']['values']
          return [] if allowed.nil?

          out_of_scope = configured - allowed
          return [] if out_of_scope.empty?

          [issue(SEVERITY_WARNING, 'country_not_available',
                 params: { 'value' => out_of_scope.join(', '), 'basis' => effective['countries']['basis'] })]
        end

        # 入口级金额区间不得超出能力声明的金额边界（未声明 → 不判，不猜）。
        def amount_issues(cap, payment_method)
          min = cap['amount_min']
          max = cap['amount_max']
          return [] if min.nil? && max.nil?

          options = Array(payment_method.effective_payment_options)
          options.filter_map do |option|
            option_min = option['amount_min']
            option_max = option['amount_max']
            out_of_range = (min && option_min && to_decimal(option_min) < min) ||
              (max && option_max && to_decimal(option_max) > max)
            next unless out_of_range

            issue(SEVERITY_WARNING, 'amount_range_out_of_capability',
                  params: { 'kind' => option['kind'].to_s })
          end
        end

        # 三态与入口配置的一致性（纯提示，不阻断）。
        def state_issues(payment_method, enabled_kinds)
          state = PallasTrade::Payments::Providers::State.state(payment_method)
          result = []

          if state == PallasTrade::Payments::Providers::State::DISABLED && enabled_kinds.any?
            result << issue(SEVERITY_INFO, 'disabled_with_active_options',
                            params: { 'count' => enabled_kinds.size.to_s })
          end

          result << issue(SEVERITY_WARNING, 'no_active_options') if payment_method.optionized? && enabled_kinds.empty?

          suspended = PallasTrade::Payments::Providers::State.suspended_kinds(payment_method)
          if suspended.any? && suspended.size < enabled_kinds.size
            result << issue(SEVERITY_INFO, 'partially_suspended',
                            params: { 'kinds' => suspended.join(', ') })
          end

          result
        end

        # ------------------------------------------------------------------ 工具

        # 已启用入口（`active != false`）的 kind；未选项化 provider 视为其隐式默认入口。
        def enabled_option_kinds(payment_method)
          options = if payment_method.optionized?
                      Array(payment_method.payment_options).select { |option| option['active'] != false }
                    else
                      Array(payment_method.effective_payment_options)
                    end

          options.map { |option| option['kind'].to_s.strip.downcase }.reject(&:blank?).uniq
        end

        def issue(severity, code, params: {})
          { 'severity' => severity, 'code' => code, 'params' => params }
        end

        def to_decimal(value)
          BigDecimal(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
