# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Store
        class RedirectsController < ResourceController
          # Resolve a path against the store's active 301 redirects.
          # GET /api/v3/store/redirects/resolve?path=/old-product
          def resolve
            path = params[:path].to_s
            redirect = current_store.redirects.active.find_by(
              from_path: PallasTrade::Redirect.normalize_path(path),
            )
            if redirect
              render json: {
                data: {
                  path: redirect.to_path,
                  status_code: redirect.status_code,
                },
              }
            else
              render json: { data: nil }
            end
          end

          protected

          def model_class
            PallasTrade::Redirect
          end
        end
      end
    end
  end
end
