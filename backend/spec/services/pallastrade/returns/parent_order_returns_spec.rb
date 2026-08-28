# frozen_string_literal: true

require 'rails_helper'

# PRD-20260828-checkout-p7 AC-004：父订单批量售后（展开子订单 → 每订单建 RA）
RSpec.describe PallasTrade::Returns::ParentOrderReturns, type: :service do
  let!(:store) { create(:store, code: 'parent_order_returns_store') }
  let(:stock_location) { create(:stock_location, name: 'WH-Returns', active: true) }
  let(:reason) { create(:return_authorization_reason) }

  # 父订单 + 2 子订单（P6 ManualSplit 拆出），全部 inventory_units 置 shipped
  let(:parent) { create(:order_ready_to_ship, store: store, line_items_count: 3, line_items_price: 10, shipment_cost: 0) }

  before do
    ids = parent.line_items.map(&:id)
    PallasTrade::Orders::ManualSplit.call(order: parent, groups: { a: [ids[0]], b: [ids[1]] })
    parent.children.each { |child| child.inventory_units.update_all(state: 'shipped') }
    parent.inventory_units.update_all(state: 'shipped')
    parent.reload
  end

  describe '#call' do
    it 'AC-004 creates one RA per order with shipped units (parent + children)' do
      result = described_class.call(parent_order: parent, stock_location: stock_location, reason: reason)

      expect(result.success?).to be true
      created = result.value
      expect(created.size).to eq(3)

      orders = [parent, *parent.reload.children]
      expect(created.map(&:order)).to match_array(orders)
      created.each do |ra|
        expect(ra.reason).to eq(reason)
        expect(ra.stock_location).to eq(stock_location)
        expect(ra.return_items.size).to eq(1)
        expect(ra.return_items.first.inventory_unit.state).to eq('shipped')
      end
    end

    it 'AC-004 skips orders without shipped inventory units' do
      # 第一个子订单的 units 置回 on_hand → 不参与
      skipped = parent.children.first
      skipped.inventory_units.update_all(state: 'on_hand')

      result = described_class.call(parent_order: parent, stock_location: stock_location, reason: reason)

      expect(result.success?).to be true
      expect(result.value.size).to eq(2)
      expect(result.value.map(&:order)).not_to include(skipped)
    end

    it 'AC-004 is idempotent — repeated call does not duplicate RAs' do
      described_class.call(parent_order: parent, stock_location: stock_location, reason: reason)

      second = described_class.call(parent_order: parent, stock_location: stock_location, reason: reason)
      expect(second.failure?).to be true
      expect(second.error.to_s).to include('No returnable orders')
      expect(PallasTrade::ReturnAuthorization.where(order_id: [parent.id, *parent.children.map(&:id)]).count).to eq(3)
    end

    it 'rejects non-parent or canceled orders' do
      single = create(:order_ready_to_ship, store: store, line_items_count: 1, line_items_price: 10, shipment_cost: 0)
      result = described_class.call(parent_order: single, stock_location: stock_location, reason: reason)
      expect(result.failure?).to be true
      expect(result.error.to_s).to include('not a parent order')
    end
  end
end
