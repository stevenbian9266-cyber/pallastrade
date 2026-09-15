module PallasTrade
  module Api
    module V3
      module Store
        module Carts
          class StoreCreditsController < Store::BaseController
            include PallasTrade::Api::V3::CartResolvable
            include PallasTrade::Api::V3::OrderLock
            include PallasTrade::Api::V3::LegacyFlowObservable

            # 余额是账户资产（游客无余额）→ 认证先于解析，保持 401 语义。
            before_action :require_authentication!
            # PRD-20260914-checkout-cart-store-credits-canonical FR-001：双解析 ——
            # `cart_` 前缀走 `pallastrade_carts`（canonical），否则走 legacy Order 型购物车。
            # 修复前：本端点仅用 legacy `find_cart!` → `cart_` id 一律 404 cart_not_found。
            before_action :find_cart_or_shopping_cart!

            # POST /api/v3/store/carts/:cart_id/store_credits
            def create
              return render_shopping_cart_store_credit(:apply) if @shopping_cart

              with_order_lock do
                result = PallasTrade.checkout_add_store_credit_service.call(
                  order: @cart,
                  amount: params[:amount].try(:to_f)
                )

                if result.success?
                  render_cart
                else
                  render_service_error(result.error)
                end
              end
            end

            # DELETE /api/v3/store/carts/:cart_id/store_credits
            def destroy
              return render_shopping_cart_store_credit(:remove) if @shopping_cart

              with_order_lock do
                result = PallasTrade.checkout_remove_store_credit_service.call(order: @cart)

                if result.success?
                  render_cart
                else
                  render_service_error(result.error)
                end
              end
            end

            private

            def find_cart_or_shopping_cart!
              if canonical_cart_request?
                @shopping_cart = current_store.shopping_carts
                                              .where(user: [nil, current_user])
                                              .active
                                              .find_by_prefix_id!(params[:cart_id])
              else
                log_legacy_usage_once(flow_type: 'legacy_cart_store_credits')
                find_cart!
              end
            end

            # §45 matrix：本行 canonical = Order Checkout Credit（canonical `cart_` 车流程
            # 同路由 + 提交时兑现）；legacy（订单型购物车）应迁至 `cart_` 购物车再走 /submit。
            def legacy_canonical_successor
              '/api/v3/store/carts'
            end

            # 车阶段错误码 → HTTP 状态（与错误码同名文案在 core en.yml）。
            STORE_CREDIT_ERROR_STATUS = {
              PallasTrade::Carts::ApplyStoreCredit::REQUIRES_LOGIN => :unauthorized,
              PallasTrade::Carts::ApplyStoreCredit::NOT_AVAILABLE => :unprocessable_content,
              PallasTrade::Carts::ApplyStoreCredit::INVALID_AMOUNT => :unprocessable_content,
              PallasTrade::Carts::ApplyStoreCredit::GIFT_CARD_CONFLICT => :unprocessable_content
            }.freeze

            def render_shopping_cart_store_credit(action)
              result =
                if action == :apply
                  PallasTrade::Carts::ApplyStoreCredit.call(cart: @shopping_cart, amount: params[:amount])
                else
                  PallasTrade::Carts::RemoveStoreCredit.call(cart: @shopping_cart)
                end

              if result.success?
                render_shopping_cart(status: action == :apply ? :created : :ok)
              else
                error_code = result.error.to_s
                render_error(
                  code: error_code.to_sym,
                  message: PallasTrade.t(error_code.to_sym),
                  status: STORE_CREDIT_ERROR_STATUS.fetch(error_code, :unprocessable_content)
                )
              end
            end
          end
        end
      end
    end
  end
end
