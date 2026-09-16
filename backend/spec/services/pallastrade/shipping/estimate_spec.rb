# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-batch-f2-stock-shipping AC-006
RSpec.describe PallasTrade::Shipping::Estimate do
  let(:store) { PallasTrade::Store.default }
  let(:product) { create(:product, store: store, status: 'active') }
  # CI 用 `bin/rails db:prepare` 建库，它会跑 `Seeds::All` —— 其中
  # `Seeds::ShippingCategories` 已经建好 Default 分类，所以这里必须复用而不是
  # `create!`（否则全量套件下必然 "Name has already been taken"）。
  let(:shipping_category) { PallasTrade::ShippingCategory.find_or_create_by!(name: 'Default') }

  # `Seeds::All` 还会留下一个 `display_on = 'both'` 的「Digital delivery」配送方式，
  # 而 `Estimate` 的 methods 是全局查询（不过滤店铺/数字商品）—— 它会被算进
  # `zero_price_method?`，把 `free_shipping` 变成 true 并抬高 methods 计数。
  # 每个 example 都从事先清空的集合开始，断言才只反映用例自己造的数据
  # （`.rspec` 引入 rails_helper，事务会回滚，不影响其他 spec）。
  before { PallasTrade::ShippingMethod.destroy_all }

  def delivery_method(**attrs)
    PallasTrade::ShippingMethod.create!(
      {
        name: 'Standard',
        display_on: 'both',
        calculator: PallasTrade::Calculator::Shipping::FlatRate.new(preferred_amount: 5),
        shipping_categories: [shipping_category]
      }.merge(attrs)
    )
  end

  describe 'transit window (FR-006/FR-009)' do
    before do
      delivery_method(name: 'Standard', estimated_transit_business_days_min: 3, estimated_transit_business_days_max: 5)
      delivery_method(name: 'Express', estimated_transit_business_days_min: 1, estimated_transit_business_days_max: 2)
    end

    it 'reports the widest window across front-end methods' do
      result = described_class.call(store: store, product: product)

      expect(result.available).to be true
      expect(result.min_days).to eq(1)
      expect(result.max_days).to eq(5)
      expect(result.to_h[:business_day_source]).to eq('weekdays')
      expect(result.to_h[:methods].size).to eq(2)
    end

    it 'falls back to the minimum when a method has no maximum' do
      PallasTrade::ShippingMethod.destroy_all
      delivery_method(estimated_transit_business_days_min: 4, estimated_transit_business_days_max: nil)

      result = described_class.call(store: store, product: product)

      expect(result.min_days).to eq(4)
      expect(result.max_days).to eq(4)
    end

    it 'reports nothing to show when there is no front-end method' do
      PallasTrade::ShippingMethod.destroy_all
      delivery_method(display_on: 'back_end')

      result = described_class.call(store: store, product: product)

      expect(result.available).to be false
      expect(result.min_days).to be_nil
      expect(result.to_h[:methods]).to eq([])
    end
  end

  describe 'digital products' do
    it 'never promises a delivery window for a digital good' do
      digital = instance_double(PallasTrade::Variant, digital?: true)

      result = described_class.call(store: store, variant: digital)

      expect(result.digital).to be true
      expect(result.available).to be false
      expect(result.min_days).to be_nil
    end
  end

  describe 'free shipping (FR-008)' do
    it 'prefers the store preference amount' do
      store.preferred_free_shipping_threshold = 50
      store.save!

      result = described_class.call(store: store.reload, product: product)

      expect(result.free_shipping_threshold.to_d).to eq(50.to_d)
      expect(result.free_shipping).to be false
    end

    it 'ignores a non-positive preference' do
      store.preferred_free_shipping_threshold = 0
      store.save!

      expect(described_class.call(store: store.reload, product: product).free_shipping_threshold).to be_nil
    end

    it 'flags a running free-shipping promotion' do
      promotion = create(:promotion, store: store, starts_at: 1.day.ago)
      PallasTrade::Promotion::Actions::FreeShipping.create!(promotion: promotion)

      expect(described_class.call(store: store, product: product).free_shipping).to be true
    end

    it 'ignores an expired free-shipping promotion' do
      promotion = create(:promotion, store: store, starts_at: 2.days.ago, expires_at: 1.day.ago)
      PallasTrade::Promotion::Actions::FreeShipping.create!(promotion: promotion)

      expect(described_class.call(store: store, product: product).free_shipping).to be false
    end
  end

  describe 'country scoping (FR-006)' do
    it 'falls back to every method when no zone matches the country' do
      delivery_method(estimated_transit_business_days_min: 2, estimated_transit_business_days_max: 3)

      result = described_class.call(store: store, country: 'ZZ', product: product)

      expect(result.available).to be true
      expect(result.to_h[:methods].size).to eq(1)
    end
  end
end
