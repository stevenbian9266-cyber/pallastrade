module PallasTrade
  module Admin
    module PaymentsHelper
      def payment_method_name(payment)
        return unless payment.payment_method.present?

        payment_method = payment.payment_method

        if can?(:update, payment_method)
          link_to payment_method.name, PallasTrade.edit_admin_payment_method_path(payment_method)
        else
          payment_method.name
        end
      end

      def available_payment_methods
        @available_payment_methods ||= PallasTrade::PaymentMethod.providers.map do |provider|
          provider.name.constantize.new
        end.delete_if { |payment_method| !payment_method.show_in_admin? || current_store.payment_methods.pluck(:type).include?(payment_method.type) }.sort_by(&:name)
      end

      # PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915-admin 切片3）—— 后台「支付方式」页签数据行：
      # 能力目录（provider 声明）∪ 已配置入口（目录外条目保留，避免保存丢数据），逐行给出当前状态。
      # 未选项化 provider 的行以其**当前生效默认入口**为勾选态（保存时勾选任一入口才置 optionized）。
      #
      # @return [Array<Hash>] [{ kind:, active:, display_name:, position:, frontend_kind: }]
      def payment_option_rows(payment_method)
        configured = payment_method.payment_options.index_by { |option| option['kind'] }
        catalog = payment_method.payment_option_catalog.index_by { |entry| entry['kind'] }
        legacy_kind = payment_method.optionized? ? nil : payment_method.effective_payment_options.first&.[]('kind')

        (catalog.keys + configured.keys).uniq.each_with_index.map do |kind, index|
          option = configured[kind]
          entry = catalog[kind] || {}

          {
            kind: kind,
            active: option ? option['active'] != false : kind == legacy_kind,
            display_name: option&.[]('display_name').presence || entry['display_name'].presence || kind,
            position: option&.[]('position').to_i.nonzero? || (index + 1),
            frontend_kind: option&.[]('frontend_kind').presence ||
              entry['frontend_kind'].presence ||
              payment_method.default_option_frontend_kind,
            # D15 切片3：入口能否被强制认证（目录声明；缺失 = 不支持 —— 不猜）
            three_d_secure: entry&.[]('three_d_secure').to_s.downcase == 'supported',
            # PALLAS-CUSTOM: D8（PRD-20260915-payments-d8 切片2）—— 适用范围（include 侧 4 维度）
            scope_form_values: payment_option_scope_form_values(payment_method, option&.[]('rule_set')),
            scope_summary: payment_method.payment_option_scope_summary(kind)
          }
        end
      end

      # PALLAS-CUSTOM: PAY-CORE-P0A（PRD-20260920-checkout 支付核心统一 · 切片 P0-A）——
      # 厂商配置诊断卡数据：三态 / 能力来源 / 账户来源 / 「能力 ∩ 账户 ∩ 市场」收窄结论 / 诊断项。
      # ⚠️ 只读：`Providers::Validate` 零写入、零网络、零资金副作用，**不参与保存路径**（写路径保持现状）。
      # @return [Hash] { state:, state_label:, ok:, rows: [{ testid:, label:, value: }], issues: [{ severity:, message: }] }
      def provider_diagnostics(payment_method)
        summary = payment_method.provider_diagnostics
        capability = payment_method.provider_capability
        account = payment_method.provider_account_config
        effective = payment_method.provider_effective_scope
        scope = PallasTrade::Payments::Providers::Config.configured_scope(payment_method)

        none_label = provider_diagnostic_text('none')
        undeclared_label = provider_diagnostic_text('undeclared')

        {
          state: summary['state'],
          state_label: provider_diagnostic_text("states.#{summary['state']}"),
          ok: summary['ok'],
          rows: [
            provider_diagnostic_row(
              'capability',
              provider_diagnostic_text('capability_source'),
              "#{provider_diagnostic_text("sources.#{capability['source']}")} · #{provider_diagnostic_list(capability['method_keys'], none_label)}"
            ),
            provider_diagnostic_row(
              'account',
              provider_diagnostic_text('account_source'),
              "#{provider_diagnostic_text("account_sources.#{account['source']}")} · " \
              "#{provider_diagnostic_list(account['methods'], undeclared_label)}" \
              "#{" · #{account['synced_at'].strftime('%Y-%m-%d %H:%M')}" if account['synced_at']}"
            ),
            provider_diagnostic_row(
              'methods',
              provider_diagnostic_text('effective_methods'),
              provider_diagnostic_effective(effective['methods'], undeclared_label)
            ),
            provider_diagnostic_row(
              'currencies',
              provider_diagnostic_text('effective_currencies'),
              provider_diagnostic_effective(effective['currencies'], undeclared_label)
            ),
            provider_diagnostic_row(
              'countries',
              provider_diagnostic_text('effective_countries'),
              provider_diagnostic_effective(effective['countries'], undeclared_label)
            ),
            provider_diagnostic_row(
              'markets',
              provider_diagnostic_text('markets'),
              provider_diagnostic_list(scope['market'].map { |id| provider_diagnostic_market_label(payment_method, id) }, none_label)
            )
          ],
          issues: summary['issues'].map do |issue|
            { severity: issue['severity'], message: provider_diagnostic_issue_message(issue) }
          end
        }
      end

      # PALLAS-CUSTOM: PAY-CORE-P0B（PRD-20260920-checkout 切片 P0-B）—— 账户配置表单数据：
      # 可选值 = 能力声明 ∩ 店铺口径（`Providers::Account.allowed_values`，与白名单同源）；
      # 选中值 = 当前 `metadata['account']`。
      def provider_account_form(payment_method)
        allowed = PallasTrade::Payments::Providers::Account.allowed_values(payment_method)
        account = payment_method.provider_account_config

        {
          allowed: allowed,
          selected: {
            'methods' => Array(account['methods']),
            'currencies' => Array(account['currencies']),
            'countries' => Array(account['countries'])
          }
        }
      end

      # PALLAS-CUSTOM: S1（PRD-20260915-admin §1.1 / FR-013）—— 已移除 P3-C「路由预览」helper。
      # 后台展示面撤下（理由：「多厂商之间谁承接」不属于「单厂商配置」页，且结论只在订单上下文成立）。
      # **路由引擎已删除（2026-09-21，收敛切片 1）**：`Payments::Routing::*` 与 `payment-routing-rspec` 均已移除
      # 全部未改动；如需再暴露后台入口，应挂在「路由策略」自己的页面上，而不是厂商详情页。

      def provider_diagnostic_row(testid, label, value)
        { testid: testid, label: label, value: value }
      end

      def provider_diagnostic_text(key, **)
        PallasTrade.t("admin.payment_methods.provider_diagnostics.#{key}", **)
      end

      def provider_diagnostic_list(values, empty_label)
        list = Array(values).map(&:to_s).reject(&:blank?)
        list.empty? ? empty_label : list.join(', ')
      end

      # 生效清单：nil = 未声明（不猜）；`[]` = 明确没有；否则列出取值 + 收窄依据。
      def provider_diagnostic_effective(narrowed, undeclared_label)
        values = narrowed['values']
        return undeclared_label if values.nil?

        "#{provider_diagnostic_list(values, provider_diagnostic_text('none'))} · " \
          "#{provider_diagnostic_text("basis.#{narrowed['basis'].tr('+', '_')}")}"
      end

      def provider_diagnostic_market_label(payment_method, market_id)
        payment_method.default_option_scope_labels.call('market', market_id).to_s
      rescue StandardError
        market_id.to_s
      end

      def provider_diagnostic_issue_message(issue)
        params = (issue['params'] || {}).symbolize_keys
        provider_diagnostic_text("issues.#{issue['code']}", **params, default: issue['code'])
      end

      # PALLAS-CUSTOM: D8（切片2）—— 范围编辑器数据源：市场 / 国家（市场国家集合）/ Zone /
      # 币种（店铺支持币种）；市场与 Zone 提交 prefixed ID，国家/币种提交 ISO 码。
      def payment_option_scope_sources(payment_method)
        store = payment_method.store

        {
          market: (store&.markets || PallasTrade::Market.none).order(:name).map { |market| [market.name, market.prefixed_id] },
          country: (store&.countries_from_markets || PallasTrade::Country.none).order(:name).map { |country| [country.name, country.iso] },
          zone: PallasTrade::Zone.order(:name).map { |zone| [zone.name, zone.prefixed_id] },
          currency: Array(store&.supported_currencies_list).map { |code| [code.to_s.upcase, code.to_s.upcase] }
        }
      end

      # 已存规则（raw 值）→ 表单字面量（市场/Zone 为 prefixed ID，国家/币种为 ISO 码）
      def payment_option_scope_form_values(payment_method, rule_set)
        selections = { market: [], country: [], zone: [], currency: [] }
        Array(PallasTrade::Payments::Availability::RuleSet.normalize(rule_set)&.[]('include')).each do |condition|
          dimension = condition['dimension'].to_sym
          next unless selections.key?(dimension)

          selections[dimension].concat(Array(condition['values']).map(&:to_s))
        end

        selections[:market] = selections[:market].filter_map { |id| payment_method.store&.markets&.find_by(id: id)&.prefixed_id }
        selections[:zone] = selections[:zone].filter_map { |id| PallasTrade::Zone.find_by(id: id)&.prefixed_id }
        selections[:country] = selections[:country].map(&:upcase)
        selections[:currency] = selections[:currency].map(&:upcase)
        selections
      end

      # PALLAS-CUSTOM: PAY-OPT-1（切片3）—— 凭证脱敏（FR-006）：已保存的 `:password` 型凭证
      # 只回显掩码（•••• + 后 4 位），页面/日志不出明文。
      def masked_password_preferences(object)
        return {} unless object.respond_to?(:preferences_of_type) && object.respond_to?(:preferences)

        object.preferences_of_type(:password).each_with_object({}) do |key, acc|
          masked = PallasTrade::Preferences::Masking.mask(object.preferences[key])
          acc[key] = masked if masked.present?
        end
      end

      # PALLAS-CUSTOM: D9（PRD-20260915-payments-d9 切片2）—— 环境选项（test / live）。
      def environment_options
        PallasTrade::PaymentMethod::ENVIRONMENTS.map do |value|
          [PallasTrade.t("admin.payment_methods.environment_#{value}", default: value.humanize), value]
        end
      end

      # 凭据健康行：key + 分级 + 轮换/到期 + 告警级别（值不进表，单独经 reveal 查看）。
      def credential_health_rows(payment_method)
        payment_method.class.password_preference_keys.map do |key|
          payment_method.credential_status(key).merge('level' => payment_method.credential_level(key))
        end
      end

      # PSP webhook 端点（不含 API key 鉴权；带环境标识）。
      def payment_webhook_endpoint_url(payment_method)
        path = "/api/v3/webhooks/payments/#{payment_method.prefixed_id}"
        store_url = payment_method.store.respond_to?(:url) ? payment_method.store.url.to_s : ''

        store_url.present? ? "#{store_url.chomp('/')}#{path}" : path
      end

      # 签名密钥（provider 可选能力）；只读展示，永远回掩码。
      def payment_webhook_signing_keys(payment_method)
        return [] unless payment_method.respond_to?(:webhook_keys)

        payment_method.webhook_keys.to_a
      end

      def masked_webhook_signing_key(key)
        secret = key.respond_to?(:signing_secret) ? key.signing_secret.to_s : ''
        return PallasTrade.t('admin.payment_methods.credential_not_set') if secret.blank?

        "#{PallasTrade::Preferences::Masking::TOKEN}#{secret.last(4)}"
      end

      # PALLAS-CUSTOM: D11 切片1（PRD-20260916-payments-d11）—— 「熔断与健康」数据面（业务方案 §67.3）：
      #   * `breaker_health_metrics`：窗口指标（provider 级口径，唯一权威 = `Health::Metrics`）
      #   * `breaker_health_rows`：逐入口状态行（选项化 provider 逐入口；未选项化 = 单入口）
      def breaker_health_metrics(payment_method, window: PallasTrade::Payments::Health::Metrics::DEFAULT_WINDOW)
        PallasTrade::Payments::Health::Metrics.call(payment_method: payment_method, window: window)
      end

      def breaker_health_rows(payment_method)
        payment_method.effective_payment_options.map do |option|
          kind = option['kind'].to_s
          state = payment_method.breaker_state(kind)

          {
            'kind' => kind,
            'display_name' => payment_method.option_display_name(kind),
            'disabled' => payment_method.soft_disabled?(kind),
            'state' => state,
            'until' => state&.[]('until'),
            'manual' => state&.[]('manual') == true
          }
        end
      end

      # 失败率展示（百分比；样本为 0 → 「—」）。
      def breaker_failure_rate_label(metrics)
        return '—' if metrics[:attempts].to_i.zero?

        "#{(metrics[:failure_rate].to_f * 100).round(1)}%"
      end

      # 平均时长展示（秒 → 「12.3s」；无终态 → 「—」）。
      def breaker_average_seconds_label(metrics)
        seconds = metrics[:avg_seconds]
        return '—' if seconds.nil?

        format('%.1fs', seconds)
      end

      # 错误类 Top 列表展示（`Err::X ×3, Err::Y ×1`；无 → 「—」）。
      def breaker_top_error_codes_label(metrics)
        codes = metrics[:top_error_codes]
        return '—' if codes.blank?

        codes.map { |entry| "#{entry['code']} ×#{entry['count']}" }.join(', ')
      end

      # 置灰窗口展示：手动 = 「人工解除」；自动 = 「自动恢复 时间」。
      def breaker_window_label(row)
        return PallasTrade.t('admin.payment_methods.breaker_manual_until') if row['manual']
        return '—' if row['until'].blank?

        PallasTrade.t('admin.payment_methods.breaker_auto_until', time: row['until'])
      end
    end
  end
end
