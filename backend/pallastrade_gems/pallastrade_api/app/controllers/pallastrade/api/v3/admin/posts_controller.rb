# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        # Admin API for blog posts — full CRUD including drafts and scheduled.
        class PostsController < ResourceController
          scoped_resource :settings

          protected

          def model_class
            PallasTrade::Post
          end

          def serializer_class
            PallasTrade.api.admin_post_serializer
          end

          def permitted_params
            params.permit(
              :title, :slug, :excerpt, :body, :author, :published_at,
              :seo_title, :seo_description, :cover_image
            )
          end

          def scope
            super.newest_first
          end
        end
      end
    end
  end
end
