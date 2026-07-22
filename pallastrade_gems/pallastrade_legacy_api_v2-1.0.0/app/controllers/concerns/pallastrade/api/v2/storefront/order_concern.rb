module PallasTrade
  module Api
    module V2
      module Storefront
        module OrderConcern
          private

          def render_order(result)
            if result.success?
              render_serialized_payload { serialized_current_order }
            else
              render_error_payload(result.error&.value || result.value)
            end
          end

          def ensure_order
            raise ActiveRecord::RecordNotFound if pallastrade_current_order.nil?
          end

          def order_token
            request.headers['X-PallasTrade-Order-Token'] ||
              request.headers['X-Spree-Order-Token'] || # deprecated compatibility fallback
              params[:order_token]
          end

          def pallastrade_current_order
            @pallastrade_current_order ||= find_pallastrade_current_order
          end

          def find_pallastrade_current_order
            PallasTrade.api.storefront_current_order_finder.new.execute(
              store: current_store,
              user: pallastrade_current_user,
              token: order_token,
              currency: current_currency
            )
          end

          def serialized_current_order
            serialize_resource(pallastrade_current_order)
          end

          def serialize_order(order)
            PallasTrade::Deprecation.warn('OrderConcern#serialize_order is deprecated and will be removed in PallasTrade 5.5. Please use `serialize_resource` method')
            serialize_resource(order)
          end
        end
      end
    end
  end
end
