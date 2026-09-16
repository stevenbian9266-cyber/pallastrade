# frozen_string_literal: true

module PallasTrade
  module Admin
    # Catalog Operations Report（PRD-20260916-catalog-operations-report；商品域审计 G-6）：
    # 把 D-1 已经在写的商品审计流水读成两个可决策的数字 —— 批量操作规模、商品维护频次。
    #
    # Read-only：没有 create/update/destroy —— 需要动手时，页面把人送回商品列表与批量操作。
    class CatalogOperationsController < BaseController
      def index
        @report = PallasTrade::Catalog::Operations::Report.call(window_days: window_days).value
        @window_days = @report[:window_days]
      end

      private

      # Anchors CanCan authorization on the product permissions, so whoever may see
      # products may see how they were maintained.
      def model_class
        PallasTrade::Product
      end

      # ?window=7|30 —— 其他值一律回落到报表默认值（不报错、不猜测）。
      def window_days
        requested = params[:window].to_i

        if PallasTrade::Catalog::Operations::Report::ALLOWED_WINDOW_DAYS.include?(requested)
          requested
        else
          PallasTrade::Catalog::Operations::Report::DEFAULT_WINDOW_DAYS
        end
      end
    end
  end
end
