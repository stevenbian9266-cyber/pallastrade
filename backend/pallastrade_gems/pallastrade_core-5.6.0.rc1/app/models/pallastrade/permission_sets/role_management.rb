# Permission set for managing roles and permissions.
#
# This permission set provides access to manage roles and user assignments.
# Note: The admin role cannot be modified.
#
# @example
#   PallasTrade.permissions.assign(:admin, PallasTrade::PermissionSets::RoleManagement)
#
module PallasTrade
  module PermissionSets
    class RoleManagement < Base
      def activate!
        can :manage, PallasTrade::Role
        can :manage, PallasTrade::RoleUser

        # Protect the admin role from modification
        cannot [:update, :destroy], PallasTrade::Role, name: ['admin']
      end
    end
  end
end
