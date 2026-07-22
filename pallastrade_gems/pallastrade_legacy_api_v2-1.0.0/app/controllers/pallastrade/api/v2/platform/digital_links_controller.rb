module PallasTrade
  module Api
    module V2
      module Platform
        class DigitalLinksController < ResourceController
          def reset
            pallastrade_authorize! :update, resource if pallastrade_current_user.present?

            if resource.reset!
              render_serialized_payload { serialize_resource(resource) }
            else
              render_error_payload(resource.errors)
            end
          end

          private

          def model_class
            PallasTrade::DigitalLink
          end

          def resource_serializer
            PallasTrade.api.platform_digital_link_serializer
          end
        end
      end
    end
  end
end
