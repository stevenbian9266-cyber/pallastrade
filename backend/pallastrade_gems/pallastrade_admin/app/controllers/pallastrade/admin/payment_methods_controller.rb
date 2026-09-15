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

      private

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
        merge_payment_options_into(attributes)
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
    end
  end
end
