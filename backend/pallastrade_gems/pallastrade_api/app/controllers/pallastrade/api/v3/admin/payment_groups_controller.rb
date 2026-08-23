# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
#
# Admin API — read-only view of payment groups (combined payment).
#
#   GET /api/v3/admin/payment_groups
#   GET /api/v3/admin/payment_groups/:id
module PallasTrade
  module Api
    module V3
      module Admin
        class PaymentGroupsController < ResourceController
          scoped_resource :payment_groups

          protected

          def model_class
            PallasTrade::PaymentGroup
          end

          def serializer_class
            PallasTrade.api.admin_payment_group_serializer
          end

          def scope
            super
          end
        end
      end
    end
  end
end
