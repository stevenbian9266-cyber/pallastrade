module PallasTrade
  module Api
    module V2
      module Platform
        class StatesController < ResourceController
          private

          def model_class
            PallasTrade::State
          end

          def scope_includes
            [:country]
          end

          def resource_serializer
            PallasTrade.api.platform_state_serializer
          end
        end
      end
    end
  end
end
