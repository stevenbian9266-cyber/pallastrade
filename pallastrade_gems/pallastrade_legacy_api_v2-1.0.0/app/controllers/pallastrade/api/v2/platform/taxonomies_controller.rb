module PallasTrade
  module Api
    module V2
      module Platform
        class TaxonomiesController < ResourceController
          private

          def model_class
            PallasTrade::Taxonomy
          end

          def scope_includes
            [:taxons, :root]
          end

          def resource_serializer
            PallasTrade.api.platform_taxonomy_serializer
          end
        end
      end
    end
  end
end
