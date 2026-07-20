# Permission set for full stock and inventory management.
#
# This permission set provides complete access to manage stock items,
# locations, and movements.
#
# @example
#   PallasTrade.permissions.assign(:warehouse_manager, PallasTrade::PermissionSets::StockManagement)
#
module PallasTrade
  module PermissionSets
    class StockManagement < Base
      def activate!
        can :manage, PallasTrade::StockItem
        can :manage, PallasTrade::StockLocation
        can :manage, PallasTrade::StockMovement
      end
    end
  end
end
