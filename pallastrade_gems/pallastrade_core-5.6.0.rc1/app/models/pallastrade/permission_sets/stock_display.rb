# Permission set for viewing stock and inventory information.
#
# This permission set provides read-only access to stock items,
# locations, and movements.
#
# @example
#   PallasTrade.permissions.assign(:warehouse_viewer, PallasTrade::PermissionSets::StockDisplay)
#
module PallasTrade
  module PermissionSets
    class StockDisplay < Base
      def activate!
        can [:read, :admin, :index], PallasTrade::StockItem
        can [:read, :admin], PallasTrade::StockLocation
        can [:read, :admin], PallasTrade::StockMovement
      end
    end
  end
end
