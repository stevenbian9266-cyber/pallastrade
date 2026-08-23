# frozen_string_literal: true

# PRD-20260823-checkout-多订单拆分与合并支付 AC-007/010
require 'rails_helper'

RSpec.describe PallasTrade::Orders::Splitter, type: :service do
  let(:store) { create(:store, code: 'order_splitter_test') }
  let(:user) { create(:user) }

  let(:order) { create(:order_with_totals, store: store, user: user, currency: 'USD') }
  let(:line_item) { order.line_items.first }
  let(:extra_line_item) { create(:line_item, order: order) }

  describe '#call' do
    it 'moves selected line items into a new split order' do
      order
      extra_line_item

      result = described_class.call(order: order, groups: { 'Warehouse B' => [extra_line_item.id] })

      expect(result).to be_success
      split_order = result.value.first
      expect(split_order).not_to eq(order)
      expect(split_order.split_from).to eq(order)
      expect(split_order.line_items).to include(extra_line_item)
      expect(order.reload.line_items).not_to include(extra_line_item)
      expect(order.line_items).to include(line_item)
    end

    it 'copies store/user/currency/addresses to the split order' do
      order
      extra_line_item

      result = described_class.call(order: order, groups: { 'g1' => [extra_line_item.id] })
      split_order = result.value.first

      expect(split_order.store).to eq(store)
      expect(split_order.user).to eq(user)
      expect(split_order.currency).to eq('USD')
      expect(split_order.bill_address).to eq(order.bill_address)
      expect(split_order.ship_address).to eq(order.ship_address)
    end

    it 'rejects splitting a completed order' do
      order.update_column(:completed_at, Time.current)
      result = described_class.call(order: order, groups: { 'g1' => [line_item.id] })
      expect(result).to be_failure
    end

    it 'rejects empty groups' do
      result = described_class.call(order: order, groups: {})
      expect(result).to be_failure
    end

    it 'recalculates totals after splitting' do
      order
      extra_line_item
      before_total = order.reload.total

      result = described_class.call(order: order, groups: { 'g1' => [extra_line_item.id] })
      split_order = result.value.first

      expect(order.reload.total).to be < before_total
      expect(split_order.reload.total).to be > 0
    end
  end
end
