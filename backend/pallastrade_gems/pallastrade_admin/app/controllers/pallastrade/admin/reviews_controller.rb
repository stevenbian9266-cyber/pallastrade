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

      # Catalog F-3 (PRD-20260916-catalog-batch-f3-review-bulk-moderation)
      # POST /admin/reviews/bulk
      #
      # Bulk approve/reject from the moderation worklist. Every review is
      # authorized and transitioned **individually** through the very same state
      # machine the single-row actions use, so audits and the public
      # "approved-only" contract stay identical — this deliberately does not
      # `update_all` the status column.
      #
      # Partial failures never roll back rows that already moved: the caller gets
      # a per-outcome report instead.
      MAX_BULK = 50
      BULK_EVENTS = { 'approve' => :approve!, 'reject' => :reject! }.freeze
      BULK_ALLOWED_FROM = {
        'approve' => %w[pending],
        'reject' => %w[pending approved]
      }.freeze

      def bulk
        event_key = params[:event].to_s
        event = BULK_EVENTS[event_key]
        ids = Array(params[:ids]).map(&:to_s).reject(&:blank?)

        return bulk_redirect(alert: PallasTrade.t('admin.reviews.bulk.unknown_event')) if event.nil?
        return bulk_redirect(alert: PallasTrade.t('admin.reviews.bulk.empty')) if ids.empty?

        if ids.size > MAX_BULK
          return bulk_redirect(alert: PallasTrade.t('admin.reviews.bulk.too_many', count: MAX_BULK))
        end

        report = { updated: 0, skipped_unauthorized: 0, skipped_invalid_state: 0, not_found: 0 }
        found = []
        ids.each do |prefixed_id|
          review = PallasTrade::Review.find_by_prefix_id(prefixed_id)
          review.nil? ? report[:not_found] += 1 : found << review
        end

        found.each do |review|
          begin
            authorize! :update, review
          rescue CanCan::AccessDenied
            report[:skipped_unauthorized] += 1
            next
          end

          unless BULK_ALLOWED_FROM[event_key].include?(review.status)
            report[:skipped_invalid_state] += 1
            next
          end

          begin
            review.public_send(event)
            report[:updated] += 1
          rescue StateMachines::InvalidTransition
            report[:skipped_invalid_state] += 1
          end
        end

        flash[:success] = PallasTrade.t('admin.reviews.bulk.result', **report)
        redirect_to PallasTrade.admin_reviews_path, status: :see_other
      end

      private

      def bulk_redirect(alert:)
        flash[:error] = alert
        redirect_to PallasTrade.admin_reviews_path, status: :see_other
      end

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
