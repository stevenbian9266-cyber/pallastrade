# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Store
        module Orders
          # CHK-P1-1A: GET Order Checkout（只读 Server-driven CheckoutView）。
          # CHK-P1-1B: PATCH Order Checkout（mutation facade —— 只 WRAP 既有
          #   Orders::*/Shipments::Update，返回最新 CheckoutView）。
          #
          # 只读 GET 无副作用；PATCH 仅更新 contact/shipping_address/物流选择，
          # 不推进 legacy 状态机、不创建 PaymentSession。访问控制复用
          # OrderResolvable（GET :show / PATCH :update；customer/token + store
          # isolation；legacy checkout 态订单按既有规则不通过订单 API 暴露）。
          class CheckoutController < Store::BaseController
            include PallasTrade::Api::V3::OrderResolvable

            before_action :find_order, only: :show
            before_action :find_order!, only: :update

            # GET /api/v3/store/orders/:order_id/checkout
            def show
              view = PallasTrade::OrderCheckout::View.call(order: @order)
              render json: serializer_class.new(view, params: serializer_params).to_h
            end

            # PATCH /api/v3/store/orders/:order_id/checkout
            # Body（每次一类）：
            #   { contact: { email } }
            #   { shipping_address: {...} } | { shipping_address_id: 'ad_...' }
            #   { delivery_rate_id: 'dr_...' }
            def update
              result = dispatch_update(@order)
              return unless result

              if result.success?
                render json: serializer_class.new(result.value, params: serializer_params).to_h
              else
                render_service_error(result.error, code: :validation_error)
              end
            end

            private

            def serializer_class
              PallasTrade::Api::V3::Store::Checkout::CheckoutSerializer
            end

            def dispatch_update(order)
              if contact_params_present?
                PallasTrade::OrderCheckout::UpdateContact.call(order: order, email: params.dig(:contact, :email))
              elsif address_params_present?
                PallasTrade::OrderCheckout::UpdateAddress.call(order: order, params: permitted_address_params)
              elsif params[:delivery_rate_id].present?
                PallasTrade::OrderCheckout::SelectShipping.call(order: order, delivery_rate_id: params[:delivery_rate_id])
              else
                render_error(code: :invalid_request, message: 'No supported checkout field provided', status: :unprocessable_entity)
                nil
              end
            end

            def contact_params_present?
              params[:contact].is_a?(ActionController::Parameters) && params[:contact][:email].present?
            end

            def address_params_present?
              params[:shipping_address_id].present? ||
                (params[:shipping_address].is_a?(ActionController::Parameters) && params[:shipping_address].present?)
            end

            def permitted_address_params
              params.permit(
                :shipping_address_id,
                shipping_address: %i[
                  id first_name last_name address1 address2 city postal_code phone company
                  country_iso state_abbr state_name
                ]
              )
            end
          end
        end
      end
    end
  end
end
