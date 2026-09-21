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

      # PALLAS-CUSTOM: 收敛切片 5 修复（2026-09-21）—— 列表只加载 `type` 可解析的行。
      # 厂商下线（类被删除）后库里可能残留指向已删类的历史行，ActiveRecord 实例化时抛
      # `ActiveRecord::SubclassNotFound`，**整条查询一起失败** → 后台支付方式列表整页 500
      # （dev 实测：HTTP 500 + 空响应体 = 用户看到的「空白页」）。
      # 在 SQL 层收窄后，脏行不参与实例化；行本身的处置见清理迁移。
      protected

      def scope
        super.loadable
      end

      private

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
        # PALLAS-CUSTOM: 收敛切片 5（2026-09-21）—— 用 selectable_providers（而非 providers）：
        # Gateway::Bogus 类保留供校验/造数，但**不再出现在后台新增下拉**中。
        PallasTrade::PaymentMethod.selectable_providers.map(&:to_s)
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

        option
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

    end
  end
end
