module PallasTrade
  module Api
    module V3
      # 订单流程标准电商改造 P1（2026-08-30）：订单域解析（Checkout 纯支付/我的订单）。
      # 与 legacy 不同，orders 现可包含 state=pending 的待支付订单（新流程）；
      # 但排除 legacy 的 checkout 态（cart/address/.../confirm——那些是 Order 同表的
      # 购物车，不应通过订单 API 暴露）。
      module OrderResolvable
        extend ActiveSupport::Concern

        LEGACY_CHECKOUT_STATES = %w[cart address delivery payment confirm].freeze

        protected

        # Find order by prefixed ID and authorize access via CanCanCan.
        # @return [PallasTrade::Order]
        def find_order
          @order = order_scope.find_by_prefix_id!(params[:id] || params[:order_id])
          authorize!(:show, @order, order_token)
          @order
        end

        # Find the order and authorize it for update.
        # @return [PallasTrade::Order]
        def find_order!
          @order = order_scope.find_by_prefix_id!(params[:id] || params[:order_id])
          authorize!(:update, @order, order_token)
          @order
        end

        # Orders visible to the current caller (JWT user or guest token), excluding
        # legacy checkout-state records (Order-as-cart).
        def order_scope
          base = current_store.orders.where.not(state: LEGACY_CHECKOUT_STATES)

          if current_user.present?
            base.where(user: current_user)
          elsif order_token.present?
            base.where(token: order_token)
          else
            base.none
          end
        end

        # Render the order as JSON using the order serializer.
        def render_order(status: :ok)
          render json: PallasTrade.api.order_serializer.new(@order.reload, params: serializer_params).to_h, status: status
        end

        # Return the order token from the request headers.
        # @return [String, nil]
        def order_token
          request.headers['x-pallastrade-token'] || request.headers['x-pallastrade-token']
        end
      end
    end
  end
end
