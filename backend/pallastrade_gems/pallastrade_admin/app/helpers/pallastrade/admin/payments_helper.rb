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
        @available_payment_methods ||= PallasTrade::PaymentMethod.providers.map { |provider| provider.name.constantize.new }.delete_if { |payment_method| !payment_method.show_in_admin? || current_store.payment_methods.pluck(:type).include?(payment_method.type) }.sort_by(&:name)
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
            position: option&.[]('position').to_i.nonzero? || index + 1,
            frontend_kind: option&.[]('frontend_kind').presence ||
                           entry['frontend_kind'].presence ||
                           payment_method.default_option_frontend_kind
          }
        end
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
    end
  end
end
