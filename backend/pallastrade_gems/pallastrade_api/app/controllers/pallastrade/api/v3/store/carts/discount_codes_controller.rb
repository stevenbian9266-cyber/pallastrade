module PallasTrade
  module Api
    module V3
      module Store
        module Carts
          class DiscountCodesController < Store::BaseController
            include PallasTrade::Api::V3::CartResolvable
            include PallasTrade::Api::V3::OrderLock

            # PRD-20260914-checkout-cart-discount-codes-canonical FR-001：
            # 双解析 —— `cart_` 前缀走 `pallastrade_carts`（canonical），否则走 legacy。
            # 修复前：本端点仅用 legacy `find_cart!` → `cart_` id 一律 403 access_denied。
            before_action :find_cart_or_shopping_cart!

            # POST  /api/v3/store/carts/:cart_id/discount_codes
            # Apply a discount code to the cart
            def create
              return render_shopping_cart_discount_code(:apply) if @shopping_cart

              with_order_lock do
                @cart.coupon_code = permitted_params[:code]

                coupon_handler.apply

                if coupon_handler.successful?
                  render_cart(status: :created)
                else
                  render_errors(coupon_handler.error)
                end
              end
            end

            # DELETE  /api/v3/store/carts/:cart_id/discount_codes/:id
            # Remove a discount code from the cart
            # :id is the discount code string (e.g., SAVE10)
            def destroy
              return render_shopping_cart_discount_code(:remove) if @shopping_cart

              with_order_lock do
                coupon_handler.remove(params[:id])

                if coupon_handler.successful?
                  render_cart
                else
                  render_errors(coupon_handler.error)
                end
              end
            end

            private

            # FR-001：canonical（`cart_`）或 legacy（订单型购物车）解析。
            # legacy 分支加观测标记（行为不变），为后续 legacy 收敛提供依据（FR-005）。
            def find_cart_or_shopping_cart!
              if params[:cart_id].to_s.start_with?('cart_')
                @shopping_cart = current_store.shopping_carts
                                              .where(user: [nil, current_user])
                                              .active
                                              .find_by_prefix_id!(params[:cart_id])
              else
                Rails.logger.info(
                  "[legacy-discount-codes] legacy cart resolution used (cart_id=#{params[:cart_id]})"
                )
                find_cart!
              end
            end

            # `cart_` 分支：应用/移除优惠码并回传购物车
            # （错误码沿用 promotion 体系：coupon_code_not_found / coupon_code_expired）。
            def render_shopping_cart_discount_code(action)
              result =
                if action == :apply
                  PallasTrade::Carts::ApplyDiscountCode.call(cart: @shopping_cart, code: permitted_params[:code])
                else
                  PallasTrade::Carts::RemoveDiscountCode.call(cart: @shopping_cart, code: params[:id])
                end

              if result.success?
                render_shopping_cart(status: action == :apply ? :created : :ok)
              else
                render_error(
                  code: result.error.to_s.to_sym,
                  message: result.error.to_s,
                  status: :unprocessable_content
                )
              end
            end

            def coupon_handler
              @coupon_handler ||= PallasTrade.coupon_handler.new(@cart, enable_gift_cards: false)
            end

            def permitted_params
              params.permit(:code)
            end
          end
        end
      end
    end
  end
end
