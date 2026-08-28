# frozen_string_literal: true

require 'rails_helper'

# PRD-20260828-admin-p6 AC-001~006：Admin 手动拆单编排（ManualSplit）
RSpec.describe PallasTrade::Orders::ManualSplit, type: :service do
  let!(:store) { create(:store, code: 'manual_split_store') }

  # 已支付可发货订单：3 行项目 ×10 + shipment cost 100 + on_hand inventory units
  let(:order) { create(:order_ready_to_ship, store: store, line_items_count: 3, line_items_price: 10, shipment_cost: 0) }

  describe '#call' do
    it 'AC-001 splits completed order into a completed child with own shipment (totals conserved)' do
      ids = order.line_items.map(&:id)

      result = described_class.call(order: order, groups: { manual: [ids[0]] })

      expect(result.success?).to be true
      child = result.value.first
      expect(child.parent).to eq(order)
      expect(child.split_from).to eq(order)

      # 子订单补为 completed + 有 completed_at
      expect(child).to be_completed
      expect(child.completed_at).to be_present

      # 子订单有独立 shipment，且 inventory_units 已迁移
      expect(child.shipments.size).to eq(1)
      expect(child.inventory_units.pluck(:shipment_id).uniq).to eq([child.shipments.first.id])
      expect(order.reload.shipments.first.inventory_units.pluck(:order_id).uniq).to contain_exactly(order.id)

      # 金额守恒：子订单 10 + 父订单剩余 20
      expect(child.item_total).to eq(BigDecimal('10'))
      expect(order.reload.item_total).to eq(BigDecimal('20'))

      # 已付金额按比例分摊（split_payments! → PaymentSplit）
      expect(child.payment_splits.sum(:captured_amount).to_f).to be > 0
    end

    it 'AC-001 splits all line items leaving an empty parent container' do
      ids = order.line_items.map(&:id)

      result = described_class.call(order: order, groups: { manual: ids })

      expect(result.success?).to be true
      child = result.value.first
      expect(child.line_items.size).to eq(3)
      expect(order.reload.line_items).to be_empty
      expect(order.reload.parent_order?).to be true
    end

    it 'AC-002 rejects canceled / empty orders' do
      canceled = create(:order, store: store, state: 'canceled')
      result = described_class.call(order: canceled, groups: { manual: [1] })
      expect(result.failure?).to be true
      expect(result.error.to_s).to include('not splittable')

      empty = create(:order, store: store)
      result = described_class.call(order: empty, groups: { manual: [1] })
      expect(result.failure?).to be true
      expect(result.error.to_s).to include('not splittable')
    end

    it 'AC-005 rejects shipped line items (shipped inventory units cannot be split)' do
      # 把第一个行项目的 inventory_units 置为 shipped → 不可拆
      li = order.line_items.first
      order.shipments.first.inventory_units.where(line_item: li).update_all(state: 'shipped')

      result = described_class.call(order: order, groups: { manual: [li.id] })

      expect(result.failure?).to be true
      expect(result.error.to_s).to include('shipped')
    end

    it 'AC-003 is idempotent — repeated split of the same groups fails without duplicates' do
      ids = order.line_items.map(&:id)

      first = described_class.call(order: order, groups: { manual: [ids[0]] })
      expect(first.success?).to be true

      # 行项目已迁移，二次拆分无有效分组
      second = described_class.call(order: order, groups: { manual: [ids[0]] })
      expect(second.failure?).to be true
      expect(order.reload.children.size).to eq(1)
    end

    it 'AC-003 ignores invalid line item ids after normalization' do
      other = create(:order_ready_to_ship, store: store, line_items_count: 1, line_items_price: 10, shipment_cost: 0)

      result = described_class.call(order: order, groups: { manual: [other.line_items.first.prefixed_id] })

      expect(result.failure?).to be true
      expect(result.error.to_s).to include('No valid split groups')
    end
  end
end
