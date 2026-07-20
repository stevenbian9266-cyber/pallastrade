module PallasTrade
  module Admin
    module PromotionsBreadcrumbConcern
      extend ActiveSupport::Concern

      included do
        add_breadcrumb_icon 'discount'
        add_breadcrumb PallasTrade.t(:promotions), :admin_promotions_path

        before_action :add_breadcrumb_for_promotion
      end

      private

      def add_breadcrumb_for_promotion
        return unless @promotion.present?
        return if @promotion.new_record?

        add_breadcrumb @promotion.name, PallasTrade.admin_promotion_path(@promotion)
      end
    end
  end
end
