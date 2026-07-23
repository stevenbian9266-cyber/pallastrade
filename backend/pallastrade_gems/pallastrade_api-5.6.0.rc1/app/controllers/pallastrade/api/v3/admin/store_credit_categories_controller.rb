module PallasTrade
  module Api
    module V3
      module Admin
        class StoreCreditCategoriesController < ResourceController
          scoped_resource :settings

          protected

          def model_class
            PallasTrade::StoreCreditCategory
          end

          def serializer_class
            PallasTrade.api.admin_store_credit_category_serializer
          end
        end
      end
    end
  end
end
