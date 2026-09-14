# frozen_string_literal: true

require 'spec_helper'

# PRD-20260914-shipping-category-name-i18n-fallback：
# 分类名是**数据**（落库字面名称 + 被商品/配送方式引用），不得写入「缺失翻译文案」；
# 历史遗留行必须可修复（合并到规范分类并迁移引用）。
RSpec.describe PallasTrade::ShippingCategory, type: :model do
  let(:store) { @default_store }

  describe '.legacy_translation_name?' do
    it 'detects the persisted missing-translation marker' do
      expect(
        described_class.legacy_translation_name?('Translation missing: en.PallasTrade.seed.shipping.categories.default')
      ).to be true
      expect(described_class.legacy_translation_name?('Default')).to be false
    end
  end

  # AC-001：新商品钩子不再依赖 I18n 输出（缺词条时曾把 missing 文案写进分类名）
  it 'assigns the literal Default name from the Product hook' do
    product = PallasTrade::Product.new(store: store, name: 'Hook test product')
    product.send(:ensure_default_shipping_category)

    expect(product.shipping_category.name).to eq(described_class::DEFAULT_NAME)
    expect(described_class.legacy_translation_name?(product.shipping_category.name)).to be false
  end

  describe '.repair_legacy_names!' do
    # AC-002：遗留行被合并到规范分类，商品与配送方式引用随之迁移，遗留行删除
    it 'merges a legacy row into the canonical category and moves references' do
      canonical = described_class.find_or_create_by!(name: described_class::DEFAULT_NAME)
      legacy = described_class.new(name: 'Translation missing: en.PallasTrade.seed.shipping.categories.default')
      legacy.save!(validate: false)

      product = create(:product_in_stock, store: store, shipping_category: legacy)
      shipping_method = create(:shipping_method, shipping_categories: [legacy])

      repaired = described_class.repair_legacy_names!

      expect(repaired).to include([legacy.id, canonical.id])
      expect(product.reload.shipping_category_id).to eq(canonical.id)
      expect(shipping_method.reload.shipping_categories).to include(canonical)
      expect(described_class.exists?(legacy.id)).to be false
    end

    # AC-003：幂等 —— 数据已规范时为空操作
    it 'is a no-op when every name is canonical' do
      described_class.find_or_create_by!(name: described_class::DEFAULT_NAME)

      expect(described_class.repair_legacy_names!).to eq([])
    end
  end
end
