# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Store
        # Blog posts — read-only, only published posts are exposed.
        class PostsController < Store::ResourceController
          include PallasTrade::Api::V3::HttpCaching

          protected

          def model_class
            PallasTrade::Post
          end

          def serializer_class
            PallasTrade.api.post_serializer
          end

          # Only published posts are visible on the storefront.
          def collection
            super.published.newest_first
          end

          # Accept slug or prefixed ID (e.g. post_abc123); drafts/scheduled 404.
          def find_resource
            resource = if params[:id].to_s.start_with?('post_')
                         scope.find_by_prefix_id!(params[:id])
                       else
                         scope.friendly.find(params[:id])
                       end
            raise ActiveRecord::RecordNotFound unless resource.published?

            resource
          end

          def scope
            super.published
          end
        end
      end
    end
  end
end
