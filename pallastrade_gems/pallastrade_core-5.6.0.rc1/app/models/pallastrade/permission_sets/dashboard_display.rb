# Permission set for viewing the admin dashboard.
#
# This permission set provides access to view the admin dashboard
# and basic admin navigation.
#
# @example
#   PallasTrade.permissions.assign(:viewer, PallasTrade::PermissionSets::DashboardDisplay)
#
module PallasTrade
  module PermissionSets
    class DashboardDisplay < Base
      def activate!
        can [:admin, :index, :show], :dashboard
      end
    end
  end
end
