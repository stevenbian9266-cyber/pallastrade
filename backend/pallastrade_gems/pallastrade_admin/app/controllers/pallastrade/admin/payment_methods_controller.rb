module PallasTrade
  module Admin
    class PaymentMethodsController < ResourceController
      include PallasTrade::Admin::PreferencesConcern
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Payment Methods；编辑页 set_breadcrumb 追加名称

      prepend_before_action :require_payment_type, only: [:new, :create]
      before_action -> { clear_empty_password_preferences(:payment_method) }, only: :update
      before_action :set_breadcrumb, only: :edit

      # POST /admin/payment_methods/:id/test_connection
      # PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915-admin 切片3）—— 凭证体检（FR-005）：
      # 只读探测（core 服务）→ 报告写 metadata['last_test_connection'] → 审计（NFR 安全）。
      # 结果不落明文：message 由服务端脱敏（凭证值 → [FILTERED]）。
      def test_connection
        outcome = PallasTrade::PaymentMethods::TestConnection.call(payment_method: @object)

        if outcome.success?
          persist_test_connection(outcome.value)
          flash[outcome.value['ok'] ? :success : :error] = test_connection_message(outcome.value)
        else
          flash[:error] = outcome.error&.to_s.presence || PallasTrade.t('admin.payment_methods.test_connection_error')
        end

        redirect_to PallasTrade.edit_admin_payment_method_path(@object), status: :see_other
      end

      # POST /admin/payment_methods/:id/reveal_credential
      # PALLAS-CUSTOM: D9（PRD-20260915-payments-d9 切片2）—— 凭据明文查看（敏感动作）：
      # owner 等价权限（默认管理员角色）+ 审计（只记 key 与 actor，**不记值**）。
      # 响应：turbo_stream（就地替换掩码元素） / json（`{ key, value }`）。
      def reveal_credential
        authorize_admin!
        return render_unknown_credential unless revealable_credential?(reveal_key)

        audit_credential_reveal(reveal_key)
        value = @object.resolved_preference(reveal_key)

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update("credential_value_#{reveal_key}", plain: value.to_s)
          end
          format.json { render json: { key: reveal_key, value: value }, status: :ok }
          format.html { redirect_to PallasTrade.edit_admin_payment_method_path(@object), status: :see_other }
        end
      end

      # POST /admin/payment_methods/:id/update_provider_account
      # PALLAS-CUSTOM: PAY-CORE-P0B（PRD-20260920-checkout 切片 P0-B）—— 账户配置写入口：
      # 登记「本商家账户已开通的支付方式 / 币种 / 国家」，供「能力 ∩ 账户 ∩ 市场」收窄使用。
      # 越界值被忽略并回显（不静默丢数据）；同值重复提交幂等（不写库、不审计）。
      # 铁律：零资金副作用 —— 只写 metadata['account'] + 审计。
      def update_provider_account
        authorize! :update, @object

        outcome = PallasTrade::Payments::Providers::Account.write!(
          @object,
          methods: params.dig(:provider_account, :methods),
          currencies: params.dig(:provider_account, :currencies),
          countries: params.dig(:provider_account, :countries),
          actor: audit_actor_label
        )

        if outcome['unchanged']
          flash[:notice] = PallasTrade.t('admin.payment_methods.provider_diagnostics.account_unchanged')
        else
          audit_provider_account_update(outcome)
          flash[:success] = PallasTrade.t('admin.payment_methods.provider_diagnostics.account_saved')
        end
        flash[:warning] = provider_account_rejection_message(outcome) if outcome['rejected'].any?

        redirect_to PallasTrade.edit_admin_payment_method_path(@object), status: :see_other
      end

      # POST /admin/payment_methods/:id/soft_disable
      # PALLAS-CUSTOM: D11 切片1（PRD-20260916-payments-d11）—— 手动软置灰（熔断兜底，业务方案 §67.3）：
      # 「摘掉一个入口」是运营动作 —— 入口级（选项化）软置灰，**必须填原因**（审计留痕），
      # 粘性生效至人工解除（`manual: true`，巡检不会自动恢复）。
      # 铁律：零资金副作用 —— 只改 metadata + 审计；不影响已建会话/已发起的支付。
      def soft_disable
        authorize! :update, @object

        reason = params[:reason].to_s.strip
        if reason.blank?
          flash[:error] = PallasTrade.t('admin.payment_methods.breaker_reason_required')
          return redirect_to PallasTrade.edit_admin_payment_method_path(@object), status: :see_other
        end

        kind = breaker_kind_param
        @object.soft_disable!(kind: kind, reason: reason, manual: true)
        audit_breaker_action('payment_option_manually_soft_disabled', kind, reason: reason)
        flash[:success] = PallasTrade.t('admin.payment_methods.breaker_soft_disabled', name: breaker_display_name(kind))

        redirect_to PallasTrade.edit_admin_payment_method_path(@object), status: :see_other
      end

      # POST /admin/payment_methods/:id/soft_enable
      # PALLAS-CUSTOM: D11 切片1 —— 解除软置灰（自动/手动通用）：清除状态 + 审计。
      def soft_enable
        authorize! :update, @object

        kind = breaker_kind_param
        state = @object.breaker_state(kind)
        @object.soft_enable!(kind)
        audit_breaker_action('payment_option_manually_soft_enabled', kind, reason: state&.[]('reason'))
        flash[:success] = PallasTrade.t('admin.payment_methods.breaker_soft_enabled', name: breaker_display_name(kind))

        redirect_to PallasTrade.edit_admin_payment_method_path(@object), status: :see_other
      end

      private

      # D11：入口 kind（选项化 provider 的入口级动作参数）。
      def breaker_kind_param
        params[:kind].presence
      end

      def breaker_display_name(kind)
        kind.present? ? @object.option_display_name(kind) : @object.name
      end

      # 熔断是运营动作：审计 actor = 后台用户 + 记录原因（`manual` 语义可回溯）。
      def audit_breaker_action(action, kind, reason: nil)
        PallasTrade::Audit.record(
          action: action,
          actor: audit_actor,
          resource: @object,
          metadata: { kind: kind, reason: reason }.compact
        )
      end

      # D9（切片2）：reveal 是敏感动作 —— 资源 update 权限 + 默认管理员角色（owner 等价）。
      def authorize_admin!
        authorize! :update, @object
        return if current_ability.can?(:manage, PallasTrade::Role.default_admin_role)

        raise CanCan::AccessDenied
      end

      def reveal_key
        params[:key].to_s
      end

      def revealable_credential?(key)
        @object.class.password_preference_keys.map(&:to_s).include?(key)
      end

      def render_unknown_credential
        render json: { error: 'unknown_credential' }, status: :unprocessable_entity
      end

      # 审计只记 key（不记值）—— 满足「看明文可追溯」且不落密钥。
      def audit_credential_reveal(key)
        PallasTrade::Audit.record(
          action: 'payment_method_credential_revealed',
          actor: audit_actor,
          resource: @object,
          metadata: { key: key }
        )
      end

      def build_resource
        if params[:payment_method].present?
          payment_type = params[:payment_method].delete(:type)
          # Find the actual class from our allowed types rather than using constantize
          payment_class = allowed_payment_types.find { |type| type == payment_type }

          if payment_class.present?
            @object = payment_class.constantize.new
          end
        end
      end

      def require_payment_type
        redirect_to PallasTrade.admin_payment_methods_path unless params.dig(:payment_method, :type).present?
      end

      def set_breadcrumb
        add_breadcrumb @payment_method.name, PallasTrade.edit_admin_payment_method_path(@payment_method)
      end

      def allowed_payment_types
        # We need to map to strings, otherwise some weird things happen with STI
        # where Rails can't find the ancestor class when we try to save the payment method.
        PallasTrade.payment_methods.map(&:to_s)
      end

      def permitted_resource_params
        attributes = params.require(:payment_method).permit(permitted_payment_method_attributes + @object.preferences.keys.map { |key| "preferred_#{key}" })
        # 归一按顺序叠加：入口（返回合并后的新 Hash）→ 环境（同一 Hash 上追加）。
        merge_environment_into(merge_payment_options_into(attributes))
      end

      # PALLAS-CUSTOM: D9（PRD-20260915-payments-d9 切片2）—— 环境归一（业务方案 §68.1）：
      #   1. 仅接受白名单值（test / live），其余值忽略（不报错，保持后台可用）；
      #   2. 切到 `test` 时强制 `storefront_visible = false`（沙箱默认不进前台）。
      def merge_environment_into(attributes)
        submitted = params.dig(:payment_method, :environment).to_s
        return attributes unless PallasTrade::PaymentMethod::ENVIRONMENTS.include?(submitted)

        attributes[:environment] = submitted
        attributes[:storefront_visible] = false if submitted == 'test'
        attributes
      end

      # PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915-admin 切片3）—— 后台「支付方式」页签写入口。
      #
      # 表单结构：payment_method[payment_options][<kind>][active|display_name|position]（前缀命名
      # 避让 `Gateway#options`）。归一规则（FR-001/002/004 + FR-007 门控）：
      #   1. 仅接受「能力目录 ∪ 已配置」的 kind —— 防注入任意入口；
      #   2. 勾选任一入口 → `metadata['optionized'] = true`（此后 0 可用入口 = 0 前台入口）；
      #      未选项化 provider 保持 optionized 缺失 → 前台回落默认入口（零回归）；
      #   3. 未随表单提交的既有 kind（API/历史数据写入）原样保留 —— 保存不丢数据。
      def merge_payment_options_into(attributes)
        submitted = params.dig(:payment_method, :payment_options)
        return attributes unless submitted.respond_to?(:each_pair)

        catalog = @object.payment_option_catalog.index_by { |entry| entry['kind'] }
        existing = @object.payment_options.index_by { |option| option['kind'] }

        normalized = []
        submitted.each_pair do |kind, entry|
          kind = kind.to_s
          next unless catalog.key?(kind) || existing.key?(kind)
          next unless entry.respond_to?(:[])

          normalized << normalize_payment_option(kind, entry, catalog[kind], existing[kind], normalized.size)
        end
        existing.each do |kind, option|
          normalized << option unless submitted.key?(kind)
        end

        metadata = (@object.metadata || {}).dup
        metadata['options'] = normalized
        metadata['optionized'] = true if @object.optionized? || normalized.any? { |option| option['active'] }

        attributes.to_h.merge(metadata: metadata)
      end

      def normalize_payment_option(kind, entry, catalog_entry, existing_option, index)
        position = entry[:position].to_s.strip.to_i
        display_name = entry[:display_name].to_s.strip.first(100).presence

        option = {
          'kind' => kind,
          'active' => ActiveModel::Type::Boolean.new.cast(entry[:active]) == true,
          'position' => position.positive? ? position : index + 1,
          'frontend_kind' => catalog_entry&.[]('frontend_kind').presence ||
                             existing_option&.[]('frontend_kind').presence ||
                             @object.default_option_frontend_kind
        }
        option['display_name'] = display_name if display_name.present?

        rule_set = merged_payment_option_rule_set(entry, existing_option)
        option['rule_set'] = rule_set if rule_set.present?
        option
      end

      # PALLAS-CUSTOM: D8（PRD-20260915-payments-d8 切片2）—— 后台「适用范围」写入口。
      #
      # 表单结构：payment_method[payment_options][<kind>][rule_set][<dimension>][]（多选值）。
      #   - v1 仅管理 include 条件；已有的 exclude 条件**原样保留**（不做排除 UI，摘要列可见）；
      #   - prefixed ID（mkt_ / zone_）解码为 raw id，并以**当前 provider 所属店铺**做作用域校验；
      #   - 国家（ISO2 白名单）/ 币种（当前店铺支持币种）校验；非法值静默丢弃；
      #   - 无有效条件 → 删除 rule_set（= 不限，零回归）。
      def merged_payment_option_rule_set(entry, existing_option)
        existing = existing_option&.[]('rule_set')
        submitted = entry[:rule_set]
        return PallasTrade::Payments::Availability::RuleSet.normalize(existing) unless submitted.respond_to?(:[])

        existing_exclude = Array(PallasTrade::Payments::Availability::RuleSet.normalize(existing)&.[]('exclude'))
        include_conditions = rule_scope_sources.filter_map do |dimension, scope|
          values = Array(submitted[dimension]).map { |value| value.to_s.strip }.reject(&:blank?).uniq
          normalized = values.filter_map { |value| decode_rule_value(dimension, value, scope) }
          next if normalized.empty?

          { 'dimension' => dimension, 'operator' => 'in', 'values' => normalized }
        end

        PallasTrade::Payments::Availability::RuleSet.normalize(
          'match' => 'all',
          'include' => include_conditions,
          'exclude' => existing_exclude
        )
      end

      def rule_scope_sources
        {
          'market' => @object.store&.markets,
          'zone' => PallasTrade::Zone.all,
          'country' => nil,
          'currency' => nil
        }
      end

      def decode_rule_value(dimension, value, scope)
        case dimension
        when 'market', 'zone'
          scope&.find_by_prefix_id(value)&.id&.to_s
        when 'country'
          iso = value.upcase
          iso if PallasTrade::Country.exists?(iso: iso)
        when 'currency'
          currency = value.upcase
          currency if rule_currency_whitelist.include?(currency)
        end
      end

      # 币种白名单 = 当前店铺支持的币种（避免配出永远不可用的入口）
      def rule_currency_whitelist
        @rule_currency_whitelist ||= Array(@object.store&.supported_currencies_list).map { |code| code.to_s.upcase }
      end

      # 只写观测值：update_columns 不触发 provider 校验（如 Stripe 的密钥校验会发远端请求）。
      # 注意：`metadata` 是 `private_metadata` 列的 API 别名（PallasTrade::Metadata），
      # update_columns 需用真实列名。
      def persist_test_connection(report)
        metadata = (@object.metadata || {}).dup
        metadata['last_test_connection'] = report
        @object.update_columns(private_metadata: metadata)

        PallasTrade::Audit.record(
          action: 'payment_method_test_connection',
          actor: audit_actor,
          resource: @object,
          metadata: { ok: report['ok'], code: report['code'] }
        )
      end

      def test_connection_message(report)
        key = report['ok'] ? 'admin.payment_methods.test_connection_ok' : 'admin.payment_methods.test_connection_failed'
        PallasTrade.t(key, code: report['code'], message: report['message'].presence || '-')
      end

      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      # PALLAS-CUSTOM: PAY-CORE-P0B —— 账户配置写入口的辅助：actor 短标签 / 审计 / 越界回显文案。
      def audit_actor_label
        actor = audit_actor
        return actor.to_s unless actor.respond_to?(:[])

        (actor[:label].presence || actor[:id]).to_s
      end

      # 审计只记「哪些维度变了、各多少条」与「被拒条数」（保持最小化，不记具体取值）。
      def audit_provider_account_update(outcome)
        PallasTrade::Audit.record(
          action: 'payment_method_provider_account_updated',
          actor: audit_actor,
          resource: @object,
          metadata: {
            methods: Array(outcome['normalized']['methods']).size,
            currencies: Array(outcome['normalized']['currencies']).size,
            countries: Array(outcome['normalized']['countries']).size,
            rejected: outcome['rejected'].transform_values { |values| Array(values).size }
          }
        )
      end

      def provider_account_rejection_message(outcome)
        summary = outcome['rejected'].map do |dimension, values|
          "#{PallasTrade.t("admin.payment_methods.provider_diagnostics.dimensions.#{dimension}")}: #{Array(values).join(', ')}"
        end.join(' · ')

        PallasTrade.t('admin.payment_methods.provider_diagnostics.account_rejected', summary: summary)
      end
    end
  end
end
