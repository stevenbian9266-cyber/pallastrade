# frozen_string_literal: true

module PallasTrade
  module Admin
    # Blog posts CRUD (CMS). Posts are store-scoped with draft/scheduled/
    # published states and multi-language content (ActionText body).
    class PostsController < ResourceController
      include PallasTrade::Admin::TableConcern
      # 面包屑由导航自动推导（P3）：Blog；对象页追加标题

      before_action :add_breadcrumb_for_post, only: [:edit, :update]

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

      def add_breadcrumb_for_post
        return unless @object.present? && @object.persisted?
        add_breadcrumb @object.title, PallasTrade.edit_admin_post_path(@object)
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
