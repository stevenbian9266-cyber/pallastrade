module PallasTrade
  module Api
    module V2
      module Platform
        class WishedItemsController < ResourceController
          private

          def scope_includes
            [:variant]
          end

          def model_class
            PallasTrade::WishedItem
          end

          def resource_serializer
            PallasTrade.api.platform_wished_item_serializer
          end
        end
      end
    end
  end
end
