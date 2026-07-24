# Permission set granting full administrative access.
#
# This permission set provides unrestricted access to all resources,
# with some safety restrictions for critical operations.
#
# @example
#   PallasTrade.permissions.assign(:admin, PallasTrade::PermissionSets::SuperUser)
#
module PallasTrade
  module PermissionSets
    class SuperUser < Base
      def activate!
        can :manage, :all

        # Safety restrictions
        cannot :cancel, PallasTrade::Order
        can :cancel, PallasTrade::Order, &:allow_cancel?
        cannot :destroy, PallasTrade::Order
        can :destroy, PallasTrade::Order, &:can_be_deleted?
        cannot [:edit, :update], PallasTrade::RefundReason, mutable: false
        cannot [:edit, :update], PallasTrade::ReimbursementType, mutable: false

        # Protect the admin role from modification
        cannot [:update, :destroy], PallasTrade::Role, name: ['admin']
      end
    end
  end
end
