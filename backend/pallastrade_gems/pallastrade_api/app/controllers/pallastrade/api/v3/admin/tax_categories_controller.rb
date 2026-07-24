module PallasTrade
  module Api
    module V3
      module Admin
        class TaxCategoriesController < ResourceController
          scoped_resource :settings

          protected

          def model_class
            PallasTrade::TaxCategory
          end

          def serializer_class
            PallasTrade.api.admin_tax_category_serializer
          end
        end
      end
    end
  end
end
