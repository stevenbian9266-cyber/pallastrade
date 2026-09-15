module PallasTrade
  module Api
    module V3
      module Store
        module Carts
          class GiftCardsController < Store::BaseController
            include PallasTrade::Api::V3::CartResolvable
            include PallasTrade::Api::V3::OrderLock
            include PallasTrade::Api::V3::LegacyFlowObservable

            # PRD-20260914-checkout-cart-gift-cards-canonical FR-001：双解析 ——
            # `cart_` 前缀走 `pallastrade_carts`（canonical），否则走 legacy Order 型购物车。
            # 修复前：本端点仅用 legacy `find_cart!` → `cart_` id 一律 404 cart_not_found
            # （storefront BFF 正是这么调 → 购物车页礼品卡功能不可用）。
            before_action :find_cart_or_shopping_cart!

            # POST /api/v3/store/carts/:cart_id/gift_cards
            def create
              return render_shopping_cart_gift_card(:apply) if @shopping_cart

              with_order_lock do
                gift_card = find_gift_card!
                return unless gift_card

                result = @cart.apply_gift_card(gift_card)

                if result.success?
                  render_cart(status: :created)
                else
                  render_service_error(result.error)
                end
              end
            end

            # DELETE /api/v3/store/carts/:cart_id/gift_cards/:id
            def destroy
              return render_shopping_cart_gift_card(:remove) if @shopping_cart

              with_order_lock do
                result = @cart.remove_gift_card

                if result.success?
                  render_cart
                else
                  render_service_error(result.error)
                end
              end
            end

            private

            # FR-001：canonical（`cart_`）或 legacy（Order 型）解析。
            # legacy 分支保留行为不变 + 观测标记（为 legacy 收敛提供量化依据）。
            def find_cart_or_shopping_cart!
              if params[:cart_id].to_s.start_with?('cart_')
                @shopping_cart = current_store.shopping_carts
                                              .where(user: [nil, current_user])
                                              .active
                                              .find_by_prefix_id!(params[:cart_id])
              else
                # 收敛切片 2：统一结构化流量日志（保留 [legacy-gift-cards] 标记便于既有查询）
                # + B5 弃用信号。
                log_legacy_usage_once(
                  flow_type: 'legacy_cart_gift_cards',
                  message: '[legacy-gift-cards] legacy cart resolution used'
                )
                find_cart!
              end
            end

            # §45 matrix：本行 canonical = Order Checkout GiftCard（canonical `cart_` 车流程
            # 同路由 + 提交时兑现）；legacy（订单型购物车）应迁至 `cart_` 购物车再走 /submit。
            def legacy_canonical_successor
              '/api/v3/store/carts'
            end

            # `cart_` 分支：车阶段**零资金副作用**（只记意图）+ 错误码与 legacy 一致。
            GIFT_CARD_ERROR_STATUS = {
              PallasTrade::Carts::ApplyGiftCard::NOT_FOUND => :not_found,
              PallasTrade::Carts::ApplyGiftCard::EXPIRED => :unprocessable_content,
              PallasTrade::Carts::ApplyGiftCard::REDEEMED => :unprocessable_content
            }.freeze

            def render_shopping_cart_gift_card(action)
              result =
                if action == :apply
                  PallasTrade::Carts::ApplyGiftCard.call(cart: @shopping_cart, code: permitted_params[:code])
                else
                  PallasTrade::Carts::RemoveGiftCard.call(cart: @shopping_cart, code: params[:id])
                end

              if result.success?
                render_shopping_cart(status: action == :apply ? :created : :ok)
              else
                error_code = result.error.to_s
                render_error(
                  code: error_code.to_sym,
                  message: PallasTrade.t(error_code.to_sym),
                  status: GIFT_CARD_ERROR_STATUS.fetch(error_code, :unprocessable_content)
                )
              end
            end

            def find_gift_card!
              gift_card = @cart.store.gift_cards.find_by(code: permitted_params[:code]&.downcase)

              if gift_card.nil?
                render_error(code: ERROR_CODES[:gift_card_not_found], message: PallasTrade.t(:gift_card_not_found), status: :not_found)
                return
              end

              if gift_card.expired?
                render_error(code: ERROR_CODES[:gift_card_expired], message: PallasTrade.t(:gift_card_expired), status: :unprocessable_content)
                return
              end

              if gift_card.redeemed?
                render_error(code: ERROR_CODES[:gift_card_already_redeemed], message: PallasTrade.t(:gift_card_already_redeemed), status: :unprocessable_content)
                return
              end

              gift_card
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
