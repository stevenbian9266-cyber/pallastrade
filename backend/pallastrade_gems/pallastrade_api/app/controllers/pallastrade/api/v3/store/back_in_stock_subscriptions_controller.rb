module PallasTrade
  module Api
    module V3
      module Store
        # Back-in-stock notifications — customers leave an email on an
        # out-of-stock product and are notified when it's back in stock.
        class BackInStockSubscriptionsController < Store::BaseController
          allow_guest_storefront_access!
          rate_limit to: PallasTrade::Api::Config[:rate_limit_register],
                     within: PallasTrade::Api::Config[:rate_limit_window].seconds,
                     store: Rails.cache,
                     only: [:create],
                     with: RATE_LIMIT_RESPONSE

          # POST /api/v3/store/products/:product_id/back_in_stock_subscriptions
          def create
            product = current_store.products.find_by_param!(params[:product_id])

            subscription = PallasTrade::BackInStockSubscription
                           .for_store(current_store)
                           .find_or_initialize_by(product: product, email: params[:email].to_s.strip.downcase)

            # Re-activate a previous subscription that was already notified.
            subscription.status = 'active'

            if subscription.save
              render json: serialize_resource(subscription), status: :created
            else
              render_errors(subscription.errors)
            end
          rescue ActiveRecord::RecordNotFound
            render_error(code: ERROR_CODES[:record_not_found], message: 'product not found', status: :not_found)
          end

          protected

          def serializer_class
            PallasTrade::Api::V3::BackInStockSubscriptionSerializer
          end
        end
      end
    end
  end
end
