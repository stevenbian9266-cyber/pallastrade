module PallasTrade
  module Api
    module V2
      module Storefront
        class CheckoutController < ::PallasTrade::Api::V2::BaseController
          include PallasTrade::Api::V2::Storefront::OrderConcern
          before_action :ensure_order

          def next
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            result = next_service.call(order: pallastrade_current_order)

            render_order(result)
          end

          def advance
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            check_if_quick_checkout

            result = advance_service.call(order: pallastrade_current_order, state: params[:state], shipping_method_id: params[:shipping_method_id])

            render_order(result)
          end

          def complete
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            result = complete_service.call(order: pallastrade_current_order)

            render_order(result)
          end

          def update
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            result = update_service.call(
              order: pallastrade_current_order,
              params: params,
              # defined in https://github.com/pallastrade/pallastrade/blob/main/core/lib/pallastrade/core/controller_helpers/strong_parameters.rb#L19
              permitted_attributes: permitted_checkout_attributes,
              request_env: request.headers.env
            )

            render_order(result)
          end

          def create_payment
            result = create_payment_service.call(order: pallastrade_current_order, params: params)

            if result.success?
              render_serialized_payload(201) { serialize_resource(pallastrade_current_order.reload) }
            else
              render_error_payload(result.error)
            end
          end

          def select_shipping_method
            result = select_shipping_method_service.call(order: pallastrade_current_order, params: params)

            render_order(result)
          end

          def add_store_credit
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            result = add_store_credit_service.call(
              order: pallastrade_current_order,
              amount: params[:amount].try(:to_f)
            )

            render_order(result)
          end

          def remove_store_credit
            pallastrade_authorize! :update, pallastrade_current_order, order_token

            result = remove_store_credit_service.call(order: pallastrade_current_order)
            render_order(result)
          end

          def shipping_rates
            result = shipping_rates_service.call(order: pallastrade_current_order)

            if result.success?
              render_serialized_payload { serialize_shipping_rates(result.value) }
            else
              render_error_payload(result.error)
            end
          end

          def payment_methods
            render_serialized_payload { serialize_payment_methods(pallastrade_current_order.collect_frontend_payment_methods) }
          end

          def validate_order_for_payment
            messages = []

            if pallastrade_current_order.present?
              validated_order, messages = PallasTrade::Cart::RemoveOutOfStockItems.call(order: pallastrade_current_order).value
              messages << PallasTrade.t(:cart_state_changed) if !validated_order.payment? && params[:skip_state].blank?
            end

            if messages.any?
              render_serialized_payload(422) do
                serialized_current_order.deep_merge({ meta: { messages: messages } })
              end
            else
              render_serialized_payload { serialized_current_order }
            end
          end

          private

          def resource_serializer
            PallasTrade.api.storefront_cart_serializer
          end

          def next_service
            PallasTrade.api.storefront_checkout_next_service
          end

          def advance_service
            PallasTrade.api.storefront_checkout_advance_service
          end

          def add_store_credit_service
            PallasTrade.api.storefront_checkout_add_store_credit_service
          end

          def remove_store_credit_service
            PallasTrade.api.storefront_checkout_remove_store_credit_service
          end

          def complete_service
            PallasTrade.api.storefront_checkout_complete_service
          end

          def update_service
            PallasTrade.api.storefront_checkout_update_service
          end

          def payment_methods_serializer
            PallasTrade.api.storefront_payment_method_serializer
          end

          def shipping_rates_service
            PallasTrade.api.storefront_checkout_get_shipping_rates_service
          end

          def shipping_rates_serializer
            PallasTrade.api.storefront_shipment_serializer
          end

          def create_payment_service
            PallasTrade.api.storefront_payment_create_service
          end

          def select_shipping_method_service
            PallasTrade.api.storefront_checkout_select_shipping_method_service
          end

          def serialize_payment_methods(payment_methods)
            payment_methods_serializer.new(payment_methods, params: serializer_params).serializable_hash
          end

          def serialize_shipping_rates(shipments)
            shipping_rates_serializer.new(
              shipments,
              params: serializer_params,
              include: [:shipping_rates, :stock_location, :line_items]
            ).serializable_hash
          end

          def check_if_quick_checkout
            pallastrade_current_order.ship_address&.quick_checkout = params[:quick_checkout] if params[:quick_checkout]
          end
        end
      end
    end
  end
end
