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
            # PALLAS-CUSTOM: D8（PRD-20260915-payments-d8 切片2）—— 适用范围（include 侧 4 维度）
          }
        end
      end

      # PALLAS-CUSTOM: S1（PRD-20260915-admin §1.1 / FR-013）—— 已移除 P3-C「路由预览」helper。
      # 后台展示面撤下（理由：「多厂商之间谁承接」不属于「单厂商配置」页，且结论只在订单上下文成立）。
      # **路由引擎已删除（2026-09-21，收敛切片 1）**：`Payments::Routing::*` 与 `payment-routing-rspec` 均已移除
      # 全部未改动；如需再暴露后台入口，应挂在「路由策略」自己的页面上，而不是厂商详情页。

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

    end
  end
end
