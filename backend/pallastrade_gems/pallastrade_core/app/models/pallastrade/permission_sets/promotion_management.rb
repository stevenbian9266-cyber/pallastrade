# Permission set for managing promotions and discounts.
#
# This permission set provides access to create and manage promotions,
# coupon codes, and promotion rules.
#
# @example
#   PallasTrade.permissions.assign(:marketing, PallasTrade::PermissionSets::PromotionManagement)
#
module PallasTrade
  module PermissionSets
    class PromotionManagement < Base
      # PALLAS-CUSTOM (2026-09-11, PRD-20260911-promotions-promo-batch5b):
      # 资源清单从 PermissionRegistry 派生（单一事实源）；`:promotions` 覆盖
      # Promotion / PromotionRule / PromotionAction，`:coupon_codes` 覆盖 CouponCode，
      # `:promotion_redemptions` 只读——与后台控制器 `authorize!` 的模型集合一致。
      grants_registry_resource :promotions, :coupon_codes
      grants_registry_resource :promotion_redemptions, actions: :read

      def activate!
        super

        # 无后台矩阵入口/无控制器的模型（仅 API 或内部使用）与通用元字段能力
        # 保持显式声明，避免注册表被非矩阵资源污染。
        can :manage, PallasTrade::PromotionCategory
        can [:read, :admin], PallasTrade::Metafield
      end
    end
  end
end
