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

        # REV-P6-8f：组合级取消编排（succeeded 组合整组/子集取消；成员退款按冻结 split 走
        # Orders::Cancel split-aware 路径）。pre-payment 组合的 cancel 仍是 combo 状态机职责。
        can :cancel, PallasTrade::PaymentCombination, &:succeeded?
        # REV-P6-8g：组合/split 只读可视化（Orders → Payment Combinations 页）
        can :read, PallasTrade::PaymentCombination
        can :read, PallasTrade::PaymentSplit

        # DSP-P7-7：争议运维（Orders → Disputes）——只读展现 + 收敛/人工标记动作
        # （动作本身仍受 P7-6/P7-7 服务的幂等与铁律约束；此处只解决「能不能进页面/能不能点」）
        can :read, PallasTrade::Dispute
      end
    end
  end
end
