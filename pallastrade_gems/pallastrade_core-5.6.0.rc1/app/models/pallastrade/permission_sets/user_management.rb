# Permission set for full user management.
#
# This permission set provides complete access to manage user accounts,
# addresses, and credit cards.
#
# @example
#   PallasTrade.permissions.assign(:customer_service, PallasTrade::PermissionSets::UserManagement)
#
module PallasTrade
  module PermissionSets
    class UserManagement < Base
      def activate!
        can :manage, PallasTrade.user_class
        can :manage, PallasTrade::Address
        can :manage, PallasTrade::CreditCard
        can [:read, :admin], PallasTrade::Metafield
      end
    end
  end
end
