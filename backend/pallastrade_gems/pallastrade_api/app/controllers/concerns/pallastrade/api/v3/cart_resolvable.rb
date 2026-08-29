module PallasTrade
  module Api
    module V3
      module CartResolvable
        extend ActiveSupport::Concern

        protected

        # Find cart by prefixed ID and authorize access via CanCanCan.
        # @return [PallasTrade::Order]
        def find_cart
          cart_id = params[:cart_id] || params[:id]
          @cart = current_store.carts.find_by_prefix_id!(cart_id)
          authorize!(:show, @cart, cart_token)
          @cart
        end

        # Find the cart and authorize it for update.
        # @return [PallasTrade::Order]
        def find_cart!
          cart_id = params[:cart_id] || params[:id]
          @cart = current_store.carts.find_by_prefix_id!(cart_id)
          authorize!(:update, @cart, cart_token)
          @cart
        end

        # ── 订单流程标准电商改造 P1（2026-08-30）：新购物车（PallasTrade::Cart）解析 ──
        # 新流程（/carts → pallastrade_carts 实体）用 shopping_carts 关联；
        # 与 legacy `find_cart`（Order 同表）前缀不同（cart_ vs or_），解析无歧义。

        # Find the new-style shopping cart (PallasTrade::Cart) and authorize for show.
        # @return [PallasTrade::Cart]
        def find_shopping_cart
          cart_id = params[:cart_id] || params[:id]
          @shopping_cart = current_store.shopping_carts.find_by_prefix_id!(cart_id)
          authorize!(:show, @shopping_cart, cart_token)
          @shopping_cart
        end

        # Find the new-style shopping cart (PallasTrade::Cart) and authorize for update.
        # @return [PallasTrade::Cart]
        def find_shopping_cart!
          cart_id = params[:cart_id] || params[:id]
          @shopping_cart = current_store.shopping_carts.find_by_prefix_id!(cart_id)
          authorize!(:update, @shopping_cart, cart_token)
          @shopping_cart
        end

        # Render the new-style shopping cart using the shopping cart serializer.
        def render_shopping_cart(status: :ok)
          render json: PallasTrade.api.shopping_cart_serializer.new(@shopping_cart, params: serializer_params).to_h, status: status
        end

        # Render the cart as JSON using the cart serializer.
        def render_cart(status: :ok)
          @cart = @cart.remove_out_of_stock_items!
          render json: PallasTrade.api.cart_serializer.new(@cart, params: serializer_params).to_h, status: status
        end

        # Render the order as JSON using the order serializer (for complete action).
        def render_order(status: :ok)
          render json: PallasTrade.api.order_serializer.new(@cart.reload, params: serializer_params).to_h, status: status
        end

        # Return the cart token from the request headers.
        # @return [String, nil]
        def cart_token
          request.headers['x-pallastrade-token'] || request.headers['x-pallastrade-token']
        end
      end
    end
  end
end
