module PallasTrade
  module Api
    module V2
      module Storefront
        class ProductsController < ::PallasTrade::Api::V2::ResourceController
          include ::PallasTrade::Api::V2::ProductListIncludes

          protected

          def sorted_collection
            collection_sorter.new(collection, current_currency, params, allowed_sort_attributes).call
          end

          def collection
            @collection ||= collection_finder.new(scope: scope, params: finder_params).execute
          end

          def resource
            # using FriendlyId so old slugs still work
            @resource ||= find_with_fallback_default_locale { scope.includes(variants: variant_includes, master: variant_includes).friendly.find(params[:id]) } || scope.includes(variants: variant_includes, master: variant_includes).friendly.find(params[:id])
          end

          def variant_includes
            [:images, :prices, { stock_items: :stock_location }]
          end

          def collection_sorter
            PallasTrade.api.storefront_products_sorter
          end

          def collection_finder
            PallasTrade.api.storefront_products_finder
          end

          def collection_serializer
            PallasTrade.api.storefront_product_serializer
          end

          def resource_serializer
            PallasTrade.api.storefront_product_serializer
          end

          def model_class
            PallasTrade::Product
          end

          def scope_includes
            product_list_includes
          end

          def allowed_sort_attributes
            super << :available_on
          end

          def collection_meta(collection)
            super(collection).merge(filters: filters_meta)
          end

          def filters_meta
            PallasTrade::Api::Products::FiltersPresenter.new(current_store, current_currency, params).to_h
          end
        end
      end
    end
  end
end
