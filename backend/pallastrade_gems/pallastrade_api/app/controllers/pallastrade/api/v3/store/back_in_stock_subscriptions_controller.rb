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
          #
          # Batch C-2 (PRD-20260915-catalog-batch-c2-sku-back-in-stock): an
          # optional `variant_id` (prefixed `variant_…`) subscribes to that SKU;
          # without it the subscription stays product-level (legacy behaviour).
          def create
            product = current_store.products.find_by_param!(params[:product_id])
            variant = resolve_variant!(product)

            subscription = PallasTrade::BackInStockSubscription
                           .for_store(current_store)
                           .find_or_initialize_by(
                             product: product,
                             variant: variant,
                             email: params[:email].to_s.strip.downcase
                           )

            # Re-activate a previous subscription that was already notified.
            subscription.status = 'active'

            if subscription.save
              render json: serialize_resource(subscription), status: :created
            else
              render_errors(subscription.errors)
            end
          rescue ActiveRecord::RecordNotFound => e
            message = e.message.include?('variant') ? 'variant not found' : 'product not found'
            render_error(code: ERROR_CODES[:record_not_found], message: message, status: :not_found)
          end

          protected

          def serializer_class
            PallasTrade::Api::V3::BackInStockSubscriptionSerializer
          end

          private

          # Resolves the optional SKU of the product.
          # @return [PallasTrade::Variant, nil]
          def resolve_variant!(product)
            raw = params[:variant_id].to_s.strip
            return nil if raw.blank?

            variant = if PallasTrade::PrefixedId.prefixed_id?(raw)
                        PallasTrade::Variant.find_by_prefix_id(raw)
                      else
                        product.variants_including_master.find_by(id: raw)
                      end

            raise ActiveRecord::RecordNotFound, 'variant not found' if variant.nil? || variant.product_id != product.id

            variant
          end
        end
      end
    end
  end
end
