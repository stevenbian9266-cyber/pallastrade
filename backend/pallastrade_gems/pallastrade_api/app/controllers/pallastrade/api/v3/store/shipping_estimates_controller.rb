module PallasTrade
  module Api
    module V3
      module Store
        # Catalog F-2 (PRD-20260916-catalog-batch-f2-stock-shipping): the PDP
        # "shipping" block's read model.
        #
        #   GET /api/v3/store/shipping_estimate?product_id=prod_xxx&country=US
        #
        # Read-only and advisory: the authoritative delivery cost is still
        # computed when the order is submitted (`Carts::Submit`), so nothing here
        # touches rates, shipments or the checkout's own selection.
        #
        # Deliberately a separate endpoint instead of a product-serializer field:
        # the answer depends on the visitor's country, and product responses are
        # cached while this must not be.
        class ShippingEstimatesController < Store::BaseController
          def show
            product = find_product

            estimate = PallasTrade::Shipping::Estimate.call(
              store: current_store,
              country: params[:country],
              product: product
            )

            render json: { data: estimate.to_h }
          end

          private

          # Store-scoped lookup so one store can never read another's product.
          # Unknown / foreign ids simply yield the store-wide estimate.
          def find_product
            id = params[:product_id].to_s
            return nil if id.blank?

            current_store.products.find_by_prefix_id(id)
          end
        end
      end
    end
  end
end
