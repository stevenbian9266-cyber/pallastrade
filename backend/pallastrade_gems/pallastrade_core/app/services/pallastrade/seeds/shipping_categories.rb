module PallasTrade
  module Seeds
    class ShippingCategories
      prepend PallasTrade::ServiceModule::Base

      def call
        # PALLAS-CUSTOM (2026-09-14, PRD-20260914-shipping-category-name-i18n-fallback):
        # 名称使用模型常量（数据）而非 `I18n.t` 输出；先修复历史遗留的缺失翻译名称，
        # 避免再次派生出重名分类。
        PallasTrade::ShippingCategory.repair_legacy_names!
        PallasTrade::ShippingCategory.find_or_create_by!(name: PallasTrade::ShippingCategory::DEFAULT_NAME)
        PallasTrade::ShippingCategory.find_or_create_by!(name: PallasTrade::ShippingCategory::DIGITAL_NAME)
      end
    end
  end
end
