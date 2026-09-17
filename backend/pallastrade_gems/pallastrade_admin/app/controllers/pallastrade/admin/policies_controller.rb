module PallasTrade
  module Admin
    class PoliciesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Policies

      before_action :set_policy_owner, only: %i[create update]

      private

      def collection_includes
        [:rich_text_translations]
      end

      def permitted_resource_params
        params.require(:policy).permit(permitted_policy_attributes + structured_return_terms_attributes)
      end

      # 结构化退货条款（PRD-20260917-catalog-json-ld-phase2 FR-005）。
      #
      # 这些是 `Policy` 上的 preference 而不是数据库列，所以表单字段名与 permit 用的都是
      # `preferred_` 前缀（与门店表单同一范式）。
      # 白名单与 `Policy#merchant_return_policy_terms` 保持一致：即使脏值进了库也会被
      # 归一化挡住，但入口挡住能避免商家「填了却不生效」的困惑。
      def structured_return_terms_attributes
        %i[
          preferred_merchant_return_policy_category
          preferred_merchant_return_policy_days
          preferred_merchant_return_policy_method
          preferred_merchant_return_policy_fees
          preferred_merchant_return_policy_countries
        ]
      end

      def update_turbo_stream_enabled?
        true
      end

      def set_policy_owner
        @policy.owner ||= current_store
      end

      def object_url(object = nil, options = {})
        target = object || @object
        PallasTrade.admin_policy_url(target&.id, options)
      end

      def edit_object_url(object = nil, options = {})
        target = object || @object
        PallasTrade.edit_admin_policy_url(target&.id, options)
      end
    end
  end
end
