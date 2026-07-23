module PallasTrade
  module Api
    module V2
      module Storefront
        class CartController < ::PallasTrade::Api::V2::BaseController
          include OrderConcern
          include CouponCodesHelper
          include PallasTrade::Api::V2::Storefront::MetadataControllerConcern

          before_action :ensure_valid_metadata, only: %i[create add_item]
          before_action :ensure_order, except: %i[create associate]
          before_action :load_variant, only: :add_item
          before_action :require_pallastrade_current_user, only: :associate

          def create
            pallastrade_authorize! :create, PallasTrade::Order

            create_cart_params = {
              user: pallastrade_current_user,
              store: current_store,
              currency: current_currency,
              public_metadata: add_item_params[:public_metadata],
              private_metadata: add_item_params[:private_metadata],
            }

            order   = pallastrade_current_order if pallastrade_current_order.present?
            order ||= create_service.call(create_cart_params).value

            render_serialized_payload(201) { serialize_resource(order) }
          end

          def add_item
            pallastrade_authorize! :update, pallastrade_current_order, order_token
            pallastrade_authorize! :show, @variant

            result = add_item_service.call(
              order: pallastrade_current_order,
              variant: @variant,
              quantity: add_item_params[:quantity],
              public_metadata: add_item_params[:public_metadata],
              private_metadata: add_item_params[:private_metadata],
              options: add_item_params[:options]
            )

            render_order(result)
          end

          def remove_line_item
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            remove_line_item_service.call(
              order: pallastrade_current_order,
              line_item: line_item
            )

            render_serialized_payload { serialized_current_order }
          end

          def empty
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            result = empty_cart_service.call(order: pallastrade_current_order)

            if result.success?
              render_serialized_payload { serialized_current_order }
            else
              render_error_payload(result.error)
            end
          end

          def destroy
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            result = destroy_cart_service.call(order: pallastrade_current_order)

            if result.success?
              head 204
            else
              render_error_payload(result.error)
            end
          end

          def set_quantity
            return render_error_item_quantity unless params[:quantity].to_i > 0

            pallastrade_authorize! :update, pallastrade_current_order, order_token

            result = set_item_quantity_service.call(order: pallastrade_current_order, line_item: line_item, quantity: params[:quantity])

            render_order(result)
          end

          def show
            pallastrade_authorize! :show, pallastrade_current_order, order_token

            render_serialized_payload { serialized_current_order }
          end

          def apply_coupon_code
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            pallastrade_current_order.coupon_code = params[:coupon_code]
            result = coupon_handler.new(pallastrade_current_order).apply

            if result.error.blank?
              pallastrade_current_order.reload
              render_serialized_payload { serialized_current_order }
            else
              render_error_payload(result.error)
            end
          end

          def remove_coupon_code
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            coupon_codes = select_coupon_codes

            return render_error_payload(I18n.t('pallastrade.api.v2.cart.no_coupon_code')) if coupon_codes.empty?

            result_errors = coupon_codes.count > 1 ? select_errors(coupon_codes) : select_error(coupon_codes)

            if result_errors.blank?
              pallastrade_current_order.reload
              render_serialized_payload { serialized_current_order }
            else
              render_error_payload(result_errors)
            end
          end

          def estimate_shipping_rates
            pallastrade_authorize! :show, pallastrade_current_order, order_token

            result = estimate_shipping_rates_service.call(order: pallastrade_current_order, country_iso: params[:country_iso])

            if result.error.blank?
              render_serialized_payload { serialize_estimated_shipping_rates(result.value) }
            else
              render_error_payload(result.error)
            end
          end

          def associate
            guest_order_token = params[:guest_order_token]
            guest_order = ::PallasTrade.api.storefront_current_order_finder.new.execute(
              store: current_store,
              user: nil,
              token: guest_order_token,
              currency: current_currency
            )

            pallastrade_authorize! :update, guest_order, guest_order_token

            result = associate_service.call(guest_order: guest_order, user: pallastrade_current_user)

            if result.success?
              render_serialized_payload { serialize_resource(guest_order) }
            else
              render_error_payload(result.error)
            end
          end

          def change_currency
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            result = change_currency_service.call(order: pallastrade_current_order, new_currency: params[:new_currency])

            render_order(result)
          end

          private

          def resource_serializer
            PallasTrade.api.storefront_cart_serializer
          end

          def create_service
            PallasTrade.api.storefront_cart_create_service
          end

          def add_item_service
            PallasTrade.api.storefront_cart_add_item_service
          end

          def empty_cart_service
            PallasTrade.api.storefront_cart_empty_service
          end

          def destroy_cart_service
            PallasTrade.api.storefront_cart_destroy_service
          end

          def set_item_quantity_service
            PallasTrade.api.storefront_cart_set_item_quantity_service
          end

          def remove_line_item_service
            PallasTrade.api.storefront_cart_remove_line_item_service
          end

          def coupon_handler
            PallasTrade.api.storefront_coupon_handler
          end

          def estimate_shipping_rates_service
            PallasTrade.api.storefront_cart_estimate_shipping_rates_service
          end

          def associate_service
            PallasTrade.api.storefront_cart_associate_service
          end

          def change_currency_service
            PallasTrade.api.storefront_cart_change_currency_service
          end

          def line_item
            @line_item ||= pallastrade_current_order.line_items.find(params[:line_item_id])
          end

          def load_variant
            @variant = current_store.variants.find(add_item_params[:variant_id])
          end

          def render_error_item_quantity
            render json: { error: I18n.t(:wrong_quantity, scope: 'pallastrade.api.v2.cart') }, status: 422
          end

          def estimate_shipping_rates_serializer
            PallasTrade.api.storefront_estimated_shipment_serializer
          end

          def serialize_estimated_shipping_rates(shipping_rates)
            estimate_shipping_rates_serializer.new(
              shipping_rates,
              params: serializer_params
            ).serializable_hash
          end

          def add_item_params
            params.permit(:quantity, :variant_id, public_metadata: {}, private_metadata: {}, options: {})
          end
        end
      end
    end
  end
end
