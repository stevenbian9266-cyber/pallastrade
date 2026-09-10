# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3c (FR-001/002): 核销台账只读端点（Admin API）。
#
#   GET /api/v3/admin/promotion_redemptions       列表（order_id / promotion_id / state 过滤 + 分页）
#   GET /api/v3/admin/promotion_redemptions/:id   详情
#
# 只读：不含 create/update/destroy；授权走 `scoped_resource :promotion_redemptions`
# （权限注册见 config/initializers/pallastrade_permission_registry.rb）。
module PallasTrade
  module Api
    module V3
      module Admin
        class PromotionRedemptionsController < ResourceController
          scoped_resource :promotion_redemptions

          # JWT 管理员走 CanCanCan；API key 主体由 ScopedAuthorization 把关（见 AdminAuthentication#current_ability）。
          before_action :authorize_redemption_read!, only: %i[index show]

          # 便捷过滤：`?order_id=order_x&promotion_id=promo_y&state=committed`
          def index
            params[:q] ||= {}
            apply_id_filter(:order_id_eq, params[:order_id])
            apply_id_filter(:promotion_id_eq, params[:promotion_id])
            params[:q][:state_eq] = params[:state] if params[:state].present?
            params[:q][:s] ||= 'created_at desc'
            super
          end

          protected

          def model_class
            PallasTrade::PromotionRedemption
          end

          def serializer_class
            PallasTrade.api.admin_promotion_redemption_serializer
          end

          def collection_includes
            %i[promotion order coupon_code]
          end

          private

          # 非法/不存在的 prefixed id → 0（恒不匹配），避免把脏值传给整型列。
          def apply_id_filter(key, value)
            return if value.blank?

            decoded = PallasTrade::PrefixedId.prefixed_id?(value) ? PallasTrade::PrefixedId.decode_prefixed_id(value) : value
            params[:q][key] = decoded.presence || 0
          end

          def authorize_redemption_read!
            return if current_api_key.present?

            authorize!(:read, PallasTrade::PromotionRedemption)
          end
        end
      end
    end
  end
end
