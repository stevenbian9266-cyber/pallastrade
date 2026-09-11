# frozen_string_literal: true

module PallasTrade
  module Admin
    # PRD-20260911-promotions-promo-batch6-pr-p9-cleanup (PR-P9-2, D2=A)
    #
    # 促销分类最小后台：PromotionCategory 是 `Promotion#promotion_category` 的归属表，
    # 原先只能通过 Admin API 维护，后台无入口（batch5b 定妆审计 D2 项）。
    # 该表**无 store_id 列**（安装级共享分类），因此范围不走 current_store；
    # ResourceController 默认 scope 已自动降级为 `model_class` 并叠加 `accessible_by`。
    class PromotionCategoriesController < ResourceController
      include PallasTrade::Admin::TableConcern

      private

      def model_class
        PallasTrade::PromotionCategory
      end

      def object_name
        'promotion_category'
      end

      def permitted_resource_params
        params.require(:promotion_category).permit(:name, :code)
      end

      def location_after_save
        PallasTrade.admin_promotion_categories_path
      end

      def location_after_destroy
        PallasTrade.admin_promotion_categories_path
      end
    end
  end
end
