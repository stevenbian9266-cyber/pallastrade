# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        class RedirectsController < ResourceController
          scoped_resource :settings

          protected

          def model_class
            PallasTrade::Redirect
          end

          def serializer_class
            PallasTrade.api.admin_redirect_serializer
          end

          def permitted_params
            params.permit(:from_path, :to_path, :status_code, :active)
          end
        end
      end
    end
  end
end
