# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-batch-f2-stock-shipping AC-001 / AC-002
RSpec.describe PallasTrade::Catalog::StockStatus do
  let(:store) { PallasTrade::Store.default }
  let(:product) { create(:product, store: store, status: 'active') }
  let(:variant) { product.master }
  let(:threshold) { 5 }

  def set_stock!(count, backorderable: false)
    variant.stock_items.update_all(count_on_hand: count, backorderable: backorderable)
    variant.reload
  end

  def bucket
    described_class.for_variant(variant, threshold: threshold)
  end

  describe 'bucketing (AC-001)' do
    it 'reports in_stock above the threshold' do
      set_stock!(6)
      expect(bucket).to eq('in_stock')
    end

    it 'reports low_stock for 1..threshold' do
      set_stock!(5)
      expect(bucket).to eq('low_stock')

      set_stock!(1)
      expect(bucket).to eq('low_stock')
    end

    it 'reports preorder for zero stock that is preorderable' do
      variant.update!(preorderable: true)
      set_stock!(0)

      expect(bucket).to eq('preorder')
    end

    it 'reports backorder for zero stock that is backorderable' do
      set_stock!(0, backorderable: true)

      expect(bucket).to eq('backorder')
    end

    it 'reports out_of_stock when nothing can supply the item' do
      set_stock!(0)
      expect(bucket).to eq('out_of_stock')
    end

    it 'never invents scarcity for variants that do not track inventory' do
      variant.update!(track_inventory: false)
      variant.stock_items.update_all(count_on_hand: 0)
      variant.reload

      expect(bucket).to eq('in_stock')
    end

    it 'agrees with the booleans the API already exposes' do
      set_stock!(2)
      expect(variant.in_stock?).to be true
      expect(bucket).to eq('low_stock')

      set_stock!(0)
      expect(variant.in_stock?).to be false
      expect(bucket).to eq('out_of_stock')
    end

    it 'reports the best bucket across a product\'s variants' do
      second = create(:variant, product: product, track_inventory: true)
      set_stock!(0)
      second.stock_items.update_all(count_on_hand: 3, backorderable: false)
      product.reload

      expect(described_class.for_product(product, threshold: threshold)).to eq('low_stock')
    end
  end

  describe 'threshold (AC-002)' do
    it 'falls back to the default for invalid values' do
      expect(described_class.normalize_threshold(0)).to eq(described_class::DEFAULT_THRESHOLD)
      expect(described_class.normalize_threshold(nil)).to eq(described_class::DEFAULT_THRESHOLD)
      expect(described_class.normalize_threshold(-3)).to eq(described_class::DEFAULT_THRESHOLD)
    end

    it 'reads the store preference' do
      store.preferred_low_stock_threshold = 2
      store.save!
      set_stock!(3)

      expect(described_class.threshold_for(store)).to eq(2)
      expect(described_class.for_variant(variant, threshold: described_class.threshold_for(store))).to eq('in_stock')
    end

    it 'normalizes a store preference of zero back to the default' do
      store.preferred_low_stock_threshold = 0
      store.save!

      expect(described_class.threshold_for(store)).to eq(described_class::DEFAULT_THRESHOLD)
    end
  end
end
