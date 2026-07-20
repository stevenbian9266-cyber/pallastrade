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
      def activate!
        can :manage, PallasTrade::Promotion
        can :manage, PallasTrade::PromotionRule
        can :manage, PallasTrade::PromotionAction
        can :manage, PallasTrade::PromotionCategory
        can :manage, PallasTrade::CouponCode
        can [:read, :admin], PallasTrade::Metafield
      end
    end
  end
end
