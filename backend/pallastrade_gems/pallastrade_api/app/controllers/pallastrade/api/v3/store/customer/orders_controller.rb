module PallasTrade
  module Api
    module V3
      module Store
        module Customer
          class OrdersController < ResourceController
            prepend_before_action :require_authentication!

            # PALLAS-CUSTOM: 父子单结构（PRD-20260824-checkout-正向订单-逆向订单链路重构或优化）
            # GET /api/v3/store/customers/me/orders/:id/children — 父订单的子订单列表
            # GET /api/v3/store/customers/me/orders/:id/parent    — 子订单的父订单
            # 只允许访问当前用户自己的订单（base_orders 约束）。

            def children
              order = base_orders.find_by_prefix_id!(params[:id])
              authorize!(:show, order)
              @collection = order.children.for_store(current_store)
              render json: {
                data: serialize_collection(@collection),
                meta: collection_meta(@collection)
              }
            end

            def parent
              order = base_orders.find_by_prefix_id!(params[:id])
              authorize!(:show, order)
              return head(:not_found) unless order.parent

              render json: serialize_resource(order.parent)
            end

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

            private

            # 当前用户自己的全部订单（不受状态选项卡 scope 过滤，便于查看任意父子订单）
            def base_orders
              current_user.orders.for_store(current_store)
            end
          end
        end
      end
    end
  end
end
