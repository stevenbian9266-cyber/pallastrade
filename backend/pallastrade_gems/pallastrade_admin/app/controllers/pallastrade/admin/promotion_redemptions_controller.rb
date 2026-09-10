# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3c (FR-005): 核销台账只读页（Promotions → Redemptions）。
# 无 new/edit/delete；表格列在 config/initializers/pallastrade_admin_tables.rb 注册。
module PallasTrade
  module Admin
    class PromotionRedemptionsController < ResourceController
      include PallasTrade::Admin::TableConcern

      private

      def model_class
        PallasTrade::PromotionRedemption
      end

      def scope
        current_store.promotion_redemptions.order(created_at: :desc)
      end

      def object_name
        'promotion_redemption'
      end

      def find_object
        scope.find_by_prefix_id!(params[:id])
      end
    end
  end
end
