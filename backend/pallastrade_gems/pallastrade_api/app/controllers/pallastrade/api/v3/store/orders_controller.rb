module PallasTrade
  module Api
    module V3
      module Store
        # 订单流程标准电商改造 P1（2026-08-30）：单订单查询。
        # 现通过 OrderResolvable 解析——范围含 state=pending 的待支付订单（新流程
        # Checkout 支付页需要读取），但排除 legacy checkout 态（Order 同表购物车）。
        class OrdersController < Store::BaseController
          include PallasTrade::Api::V3::OrderResolvable

          # GET /api/v3/store/orders/:id
          # Single order lookup — accessible via order token (guests) or JWT (authenticated users).
          # Uses the `:show` ability (own orders are always viewable, including
          # completed-but-unpaid orders on the checkout payment page); mutations
          # (shipping address / payment sessions) keep the stricter `:update` ability.
          before_action :find_order

          def show
            render json: serializer_class.new(@order, params: serializer_params).to_h
          end

          private

          def serializer_class
            PallasTrade.api.order_serializer
          end
        end
      end
    end
  end
end
