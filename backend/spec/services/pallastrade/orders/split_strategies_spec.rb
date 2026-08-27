# frozen_string_literal: true

require 'rails_helper'

# PRD-20260826-checkout-实施-p2-统一拆单引擎
# AC-009：SplitStrategies 策略分组
RSpec.describe 'PallasTrade::Orders::SplitStrategies' do
  let(:store) { create(:store, code: 'split_strategy_store') }

  describe PallasTrade::Orders::SplitStrategies::ByStore do
    it 'groups line items by their product store (AC-009)' do
      store_b = create(:store, code: 'split_strategy_store_b')
      product_a = create(:product, store: store)
      product_b = create(:product, store: store_b)

      order = create(:order, store: store)
      li_a = create(:line_item, order: order, variant: product_a.default_variant)
      li_b = create(:line_item, order: order, variant: product_b.default_variant)

      groups = described_class.new.groups_for(order)

      expect(groups.size).to eq(2)
      expect(groups.values.flatten).to contain_exactly(li_a.id, li_b.id)
    end
  end

  describe PallasTrade::Orders::SplitStrategies::ByStockLocation do
    it 'groups line items by the assigned stock location (AC-009)' do
      wh_a = create(:stock_location, name: 'WH-A', active: true)
      wh_b = create(:stock_location, name: 'WH-B', active: true)
      product_a = create(:product, store: store)
      product_b = create(:product, store: store)
      variant_a = product_a.default_variant
      variant_b = product_b.default_variant
      create(:stock_item, variant: variant_a, stock_location: wh_a, count_on_hand: 5)
      create(:stock_item, variant: variant_b, stock_location: wh_b, count_on_hand: 5)

      order = create(:order, store: store)
      create(:line_item, order: order, variant: variant_a)
      create(:line_item, order: order, variant: variant_b)

      groups = described_class.new.groups_for(order)

      expect(groups.size).to eq(2)
      expect(groups.values.flatten.size).to eq(2)
    end
  end
end
