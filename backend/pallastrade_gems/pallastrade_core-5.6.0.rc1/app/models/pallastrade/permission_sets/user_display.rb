# Permission set for viewing users and related information.
#
# This permission set provides read-only access to user accounts,
# addresses, and credit cards.
#
# @example
#   PallasTrade.permissions.assign(:support_staff, PallasTrade::PermissionSets::UserDisplay)
#
module PallasTrade
  module PermissionSets
    class UserDisplay < Base
      def activate!
        can [:read, :admin, :index], PallasTrade.user_class
        can [:read, :admin], PallasTrade::Address
        can [:read, :admin], PallasTrade::CreditCard
      end
    end
  end
end
