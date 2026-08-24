module PallasTrade
  module Api
    module V3
      module Store
        module Customer
          class OrdersController < ResourceController
            prepend_before_action :require_authentication!

            protected

            def model_class
              PallasTrade::Order
            end

            def serializer_class
              PallasTrade.api.order_serializer
            end

            def set_parent
              @parent = current_user
            end

            def parent_association
              :orders
            end

            # PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
            # ?scope=unpaid → placed-but-unpaid orders (for combined payment picker).
            # Accepts both top-level `scope` and Ransack-wrapped `q[scope]` (older
            # SDK builds wrapped non-passthrough params).
            #
            # PALLAS-CUSTOM: 订单状态选项卡（PRD-20260824-checkout-订单列表状态选项卡）
            # scope=processing → paid but not shipped (fulfillment pending/ready/partial)
            # scope=shipped    → fulfillment_status = shipped
            # scope=canceled   → status = canceled
            # scope=all        → every order (no status filter)
            # default          → complete (completed_at present)
            def scope
              base = super.for_store(current_store)
              scope_param = params[:scope] || params.dig(:q, :scope)
              case scope_param
              when 'unpaid' then base.unpaid_for_combined_payment
              when 'processing'
                base.where(fulfillment_status: %w[pending ready partial])
                    .where.not(payment_state: %w[balance_due credit_owed])
              when 'shipped' then base.where(fulfillment_status: 'shipped')
              when 'canceled' then base.where(status: 'canceled')
              when 'all' then base
              else base.complete
              end
            end
          end
        end
      end
    end
  end
end
