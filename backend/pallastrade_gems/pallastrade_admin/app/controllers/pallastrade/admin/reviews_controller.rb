# frozen_string_literal: true

module PallasTrade
  module Admin
    # Admin moderation of customer product reviews (P0-4).
    # Admins can approve / reject / delete reviews; only approved reviews are
    # public on the storefront and counted in the product's average rating.
    class ReviewsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern
      # 面包屑由导航配置自动推导（P5）：Catalog > Reviews

      # PATCH /admin/reviews/:id/approve
      def approve
        @review = find_review
        @review.approve!
        flash[:success] = PallasTrade.t('admin.reviews.approved')
        redirect_to PallasTrade.admin_reviews_path, status: :see_other
      end

      # PATCH /admin/reviews/:id/reject
      def reject
        @review = find_review
        @review.reject!
        flash[:success] = PallasTrade.t('admin.reviews.rejected')
        redirect_to PallasTrade.admin_reviews_path, status: :see_other
      end

      private

      def find_review
        scope.find_by_prefix_id!(params[:id])
      end

      def model_class
        PallasTrade::Review
      end

      def scope
        current_store.reviews
      end

      def object_name
        'review'
      end

      def location_after_destroy
        PallasTrade.admin_reviews_path
      end
    end
  end
end
