module PallasTrade
  module Api
    module V2
      module Platform
        class TaxCategoriesController < ResourceController
          private

          def model_class
            PallasTrade::TaxCategory
          end

          def scope_includes
            [:tax_rates]
          end

          def resource_serializer
            PallasTrade.api.platform_tax_category_serializer
          end
        end
      end
    end
  end
end
