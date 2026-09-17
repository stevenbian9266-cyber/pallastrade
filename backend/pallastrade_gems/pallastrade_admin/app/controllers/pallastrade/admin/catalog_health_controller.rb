# frozen_string_literal: true

module PallasTrade
  module Admin
    # Catalog Health V1 (PRD-20260915-admin-catalog-health-v1):
    # the merchant worklist that aggregates the seven actionable catalog issues
    # and links every count to the page that can fix them.
    #
    # Read-only: there is no create/update/destroy here — remediation happens in
    # the products list (bulk operations), Product Translations or Redirects.
    class CatalogHealthController < BaseController
      def index
        @report = PallasTrade::CatalogHealth::Report.call(current_store)
        # G-7（PRD-20260916-catalog-health-trend-snapshot）：计数是「现在」，趋势是「在变好还是变差」。
        # 趋势只读快照表；没有两条可比快照时方向为 unknown（页面必须如实显示，不得当成持平）。
        @trend = PallasTrade::CatalogHealth::Trend.call(current_store)
        # PRD-20260917-catalog-health-coverage-ratios：计数没有分母就不可决策（「23 个缺 SEO」
        # 在 25 个商品的店里是灾难、在 5000 个的店里是噪声）—— 分子复用 Issues.count，分母各自自洽。
        @coverage = PallasTrade::CatalogHealth::Coverage.call(current_store)
        # PRD-20260917-catalog-health-score：总分只是「一眼看结论」，可解释性靠它的明细表 ——
        # 不可计算的维度既不按 0 也不按 1 计入，页面照实标注原因。
        @score = PallasTrade::CatalogHealth::Score.call(current_store)
      end

      helper_method :catalog_health_target_path

      private

      # Anchors CanCan authorization on the product permissions (`read` +
      # `admin` are granted by PallasTrade::PermissionSets::ProductDisplay), so
      # whoever may see products may see their health.
      def model_class
        PallasTrade::Product
      end

      # @param issue [PallasTrade::CatalogHealth::Report::Issue]
      # @return [String] path that lets the merchant act on that issue
      def catalog_health_target_path(issue)
        return PallasTrade.admin_products_path(issue.params) if issue.target == :products

        PallasTrade.public_send("admin_#{issue.target}_path")
      end
    end
  end
end
