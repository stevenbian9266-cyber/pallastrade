# frozen_string_literal: true

module PallasTrade
  module Admin
    # Blog posts CRUD (CMS). Posts are store-scoped with draft/scheduled/
    # published states and multi-language content (ActionText body).
    class PostsController < ResourceController
      include PallasTrade::Admin::TableConcern

      private

      def model_class
        PallasTrade::Post
      end

      def scope
        current_store.posts
      end

      def object_name
        'post'
      end

      def permitted_resource_params
        params.require(:post).permit(
          :title, :slug, :excerpt, :body, :author, :published_at,
          :seo_title, :seo_description, :cover_image
        )
      end

      def location_after_save
        PallasTrade.admin_posts_path
      end

      def location_after_destroy
        PallasTrade.admin_posts_path
      end
    end
  end
end
