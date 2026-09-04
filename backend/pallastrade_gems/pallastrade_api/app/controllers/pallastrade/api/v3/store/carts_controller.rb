# PALLAS-CUSTOM: Scope current carts and return replay-safe submit/successor data.
module PallasTrade
  module Api
    module V3
      module Store
        # 订单流程标准电商改造 P1（2026-08-30）：购物车 API 切换为新 Cart 实体
        # （pallastrade_carts）。与 legacy（Order 同表）的差异：
        # - 解析用 current_store.shopping_carts（cart_ 前缀，与 Order 的 or_ 前缀区分）
        # - 提交订单 = POST /carts/:id/submit（→ 创建 Order + Cart converted），
        #   替代 legacy 的 POST /carts/:id/complete（推进 checkout 状态机）
        # - 支付/物流/优惠券等嵌套资源迁移到 orders 域（支付会话）或确认页（物流）
        class CartsController < Store::ResourceController
          include PallasTrade::Api::V3::CartResolvable

          skip_before_action :set_resource
          prepend_before_action :require_authentication!, only: [:index, :associate]

          # GET /api/v3/store/carts/:id
          # Returns shopping cart by prefixed ID (cart_xxx).
          def show
            find_shopping_cart
            render_shopping_cart
          end

          # POST /api/v3/store/carts
          # Creates a new shopping cart (pallastrade_carts).
          # Can be created by guests or authenticated customers.
          def create
            result = PallasTrade::Carts::Create.call(
              params: permitted_params.merge(
                user: current_user,
                store: current_store,
                currency: current_currency,
                locale: current_locale
              )
            )

            if result.success?
              @shopping_cart = result.value
              render_shopping_cart(status: :created)
            else
              render_service_error(result.error.to_s)
            end
          end

          # PATCH /api/v3/store/carts/:id
          # Updates cart info (email, addresses, shipping method, items).
          def update
            find_shopping_cart!

            result = PallasTrade::Carts::Update.call(
              cart: @shopping_cart,
              params: permitted_params
            )

            if result.success?
              render_shopping_cart
            else
              render_service_error(result.error, code: ERROR_CODES[:validation_error])
            end
          end

          # DELETE /api/v3/store/carts/:id
          # Deletes the cart (cascades cart_items).
          def destroy
            find_shopping_cart!
            @shopping_cart.destroy
            head :no_content
          end

          # PATCH /api/v3/store/carts/:id/associate
          # Associates a guest cart with the currently authenticated user.
          # Requires: JWT authentication + cart ID in URL.
          def associate
            find_shopping_cart_for_association
            @shopping_cart.update!(user: current_user)
            render_shopping_cart
          end

          # POST /api/v3/store/carts/:id/submit
          # ★提交订单：校验勾选商品 → 从 Cart 快照创建 Order（state=pending）
          # + Cart → converted。返回 Order（or_ 前缀）供前端跳转 /checkout/[orderId]。
          def submit
            # `show` ownership is intentional: a converted Cart must remain readable
            # by its owner so a retried POST can replay the original Order.
            find_shopping_cart

            result = PallasTrade::Carts::Submit.call(cart: @shopping_cart)

            if result.success?
              @order = result.value
              payload = PallasTrade.api.order_serializer.new(@order, params: serializer_params).to_h
              payload[:successor_cart] = serialize_successor_cart(@order)
              render json: payload
            else
              render_service_error(
                result.error.to_s.presence || 'Could not submit order',
                code: ERROR_CODES[:cart_cannot_complete]
              )
            end
          end

          protected

          def model_class
            PallasTrade::Cart
          end

          def serializer_class
            PallasTrade.api.shopping_cart_serializer
          end

          def scope
            current_store.shopping_carts.active.where(user: current_user).order(updated_at: :desc)
          end

          private

          def permitted_params
            params.permit(
              :email,
              :customer_note,
              :currency,
              :locale,
              :shipping_address_id,
              :billing_address_id,
              :shipping_method_id,
              shipping_address: address_params,
              billing_address: address_params,
              metadata: {},
              items: item_params
            )
          end

          def address_params
            [
              :id, :first_name, :last_name,
              :address1, :address2,
              :city, :postal_code, :phone, :company,
              :country_iso, :state_abbr, :state_name, :quick_checkout
            ]
          end

          def item_params
            [:variant_id, :quantity, :selected, { metadata: {}, options: {} }]
          end

          def serialize_successor_cart(order)
            successor_id = order.metadata.with_indifferent_access[:successor_cart_id]
            return nil if successor_id.blank?

            successor = current_store.shopping_carts.active.find_by_prefix_id(successor_id)
            return nil unless successor

            PallasTrade.api.shopping_cart_serializer.new(successor, params: serializer_params).to_h
          end

          # Find guest cart (no user) or cart already owned by current user (idempotent).
          def find_shopping_cart_for_association
            @shopping_cart = current_store.shopping_carts.where(user: [nil, current_user]).find_by_prefix_id!(params[:id])
          end
        end
      end
    end
  end
end
