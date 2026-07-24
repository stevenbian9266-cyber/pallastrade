# Permission set for full order management.
#
# This permission set provides complete access to manage orders,
# including creating, updating, and processing payments and shipments.
#
# @example
#   PallasTrade.permissions.assign(:order_manager, PallasTrade::PermissionSets::OrderManagement)
#
module PallasTrade
  module PermissionSets
    class OrderManagement < Base
      def activate!
        can :manage, PallasTrade::Order
        can :manage, PallasTrade::Payment
        can :manage, PallasTrade::Shipment
        can :manage, PallasTrade::Adjustment
        can :manage, PallasTrade::LineItem
        can :manage, PallasTrade::ReturnAuthorization
        can :manage, PallasTrade::CustomerReturn
        can :manage, PallasTrade::Reimbursement
        can :manage, PallasTrade::Refund
        can :manage, PallasTrade::StoreCredit
        can :manage, PallasTrade::GiftCard

        # Order-specific restrictions
        cannot :cancel, PallasTrade::Order
        can :cancel, PallasTrade::Order, &:allow_cancel?
        cannot :destroy, PallasTrade::Order
        can :destroy, PallasTrade::Order, &:can_be_deleted?
      end
    end
  end
end
