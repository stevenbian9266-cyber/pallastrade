# frozen_string_literal: true

# PALLAS-CUSTOM (2026-09-14, PRD-20260914-shipping-category-name-i18n-fallback):
# 修复历史上把「缺失翻译文案」当成分类名落库的遗留数据（后台显示 Translation missing: …）。
namespace :pallastrade do
  namespace :shipping_categories do
    desc 'Repair shipping categories whose name holds a missing-translation string (merge into Default/Digital)'
    task repair_legacy_names: :environment do
      repaired = PallasTrade::ShippingCategory.repair_legacy_names!

      if repaired.empty?
        puts '✅ No legacy shipping category names found.'
      else
        repaired.each do |legacy_id, canonical_id|
          puts "✅ Merged shipping category #{legacy_id} into #{canonical_id}"
        end
        puts "✅ Repaired #{repaired.size} shipping category row(s)."
      end
    end
  end
end
