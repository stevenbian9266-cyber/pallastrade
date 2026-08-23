# Permission set for viewing orders and related resources.
#
# This permission set provides read-only access to orders and associated
# models like payments, shipments, and refunds.
#
# @example
#   PallasTrade.permissions.assign(:customer_service, PallasTrade::PermissionSets::OrderDisplay)
#
module PallasTrade
  module PermissionSets
    class OrderDisplay < Base
      def activate!
        can [:read, :admin, :index], PallasTrade::Order
        can [:read, :admin], PallasTrade::Payment
        # PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
        can [:read, :admin, :index], PallasTrade::PaymentGroup
        can [:read, :admin], PallasTrade::Shipment
        can [:read, :admin], PallasTrade::Adjustment
        can [:read, :admin], PallasTrade::LineItem
        can [:read, :admin], PallasTrade::ReturnAuthorization
        can [:read, :admin], PallasTrade::CustomerReturn
        can [:read, :admin], PallasTrade::Reimbursement
        can [:read, :admin], PallasTrade::Refund
        can [:read, :admin], PallasTrade::StoreCredit
        can [:read, :admin], PallasTrade::GiftCard
      end
    end
  end
end
