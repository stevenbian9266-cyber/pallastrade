module PallasTrade
  module Api
    module V2
      module Storefront
        class StoresController < ::PallasTrade::Api::V2::ResourceController
          def current
            render_serialized_payload { serialize_resource(current_store) }
          end

          private

          def model_class
            PallasTrade::Store
          end

          def resource
            @resource ||= scope.find_by!(code: params[:code])
          end

          def resource_serializer
            PallasTrade.api.storefront_store_serializer
          end
        end
      end
    end
  end
end
