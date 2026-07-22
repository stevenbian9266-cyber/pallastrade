module PallasTrade
  module Api
    module V2
      module Storefront
        class TaxonsController < ::PallasTrade::Api::V2::ResourceController
          private

          def collection_serializer
            PallasTrade.api.storefront_taxon_serializer
          end

          def resource_serializer
            PallasTrade.api.storefront_taxon_serializer
          end

          def collection_finder
            PallasTrade.api.storefront_taxon_finder
          end

          def paginated_collection
            @paginated_collection ||= collection_paginator.new(collection, params).call
          end

          def resource
            @resource ||= find_with_fallback_default_locale { scope.find_by(permalink: params[:id]) } || scope.find(params[:id])
          end

          def model_class
            PallasTrade::Taxon
          end

          def scope_includes
            node_includes = %i[parent taxonomy]

            {
              parent: node_includes,
              children: node_includes,
              taxonomy: [root: node_includes],
              image_attachment: :blob
            }
          end

          def serializer_params
            super.merge(include_products: action_name == 'show')
          end
        end
      end
    end
  end
end
