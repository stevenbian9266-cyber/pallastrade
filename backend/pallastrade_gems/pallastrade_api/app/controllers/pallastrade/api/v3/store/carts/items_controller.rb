module PallasTrade
  module Api
    module V3
      module Store
        module Carts
          # 订单流程标准电商改造 P1（2026-08-30）：购物车行 API（pallastrade_cart_items）。
          # 操作新 Cart 实体（cart_ 前缀）；支持 selected 勾选标记（本次结算范围）。
          class ItemsController < Store::BaseController
            include PallasTrade::Api::V3::CartResolvable

            before_action :find_shopping_cart!

            # POST  /api/v3/store/carts/:cart_id/items
            def create
              result = PallasTrade::Carts::UpsertItems.call(
                cart: @shopping_cart,
                items: [permitted_params.merge(variant_id: variant.prefixed_id)]
              )

              if result.success?
                render_shopping_cart(status: :created)
              else
                render_service_error(result.error, code: ERROR_CODES[:insufficient_stock])
              end
            end

            # PATCH  /api/v3/store/carts/:cart_id/items/:id
            # 更新数量 / 勾选状态 / metadata。
            def update
              @cart_item = @shopping_cart.cart_items.find_by_prefix_id!(params[:id])

              @cart_item.metadata = @cart_item.metadata.merge(permitted_params[:metadata].to_h) if permitted_params[:metadata].present?
              @cart_item.selected = permitted_params[:selected] if permitted_params.key?(:selected)
              @cart_item.quantity = permitted_params[:quantity] if permitted_params[:quantity].present?

              if @cart_item.changed?
                if @cart_item.valid?
                  @cart_item.save!
                  @shopping_cart.touch_last_activity!
                  render_shopping_cart
                else
                  render_service_error(@cart_item.errors.full_messages.to_sentence, code: ERROR_CODES[:invalid_quantity])
                end
              else
                render_shopping_cart
              end
            end

            # DELETE  /api/v3/store/carts/:cart_id/items/:id
            def destroy
              @cart_item = @shopping_cart.cart_items.find_by_prefix_id!(params[:id])
              @cart_item.destroy
              @shopping_cart.touch_last_activity!
              render_shopping_cart
            end

            private

            def variant
              @variant ||= current_store.variants.accessible_by(current_ability).find_by_prefix_id!(permitted_params[:variant_id])
            end

            def permitted_params
              params.permit(:variant_id, :quantity, :selected, :metadata)
            end
          end
        end
      end
    end
  end
end
