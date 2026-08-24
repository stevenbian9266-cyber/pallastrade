# frozen_string_literal: true

# PRD-20260823-checkout-多订单拆分与合并支付 AC-007/010
require 'rails_helper'

RSpec.describe PallasTrade::Orders::Splitter, type: :service do
  let(:store) { create(:store, code: 'order_splitter_test') }
  let(:user) { create(:user) }

  # order_with_line_items 会通过 update_with_updater! 正确重算 total（order_with_totals 不重算，属 pre-existing 缺陷）
  let(:order) { create(:order_with_line_items, store: store, user: user, currency: 'USD') }
  let(:line_item) { order.line_items.first }
  # 显式价格：确保拆分前后总额可比较（默认 price=0 会导致拆走 0 金额行项目 total 不变）
  let(:extra_line_item) { create(:line_item, order: order, price: 50) }

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

    it 'AC-006/029: 拆出的子订单 parent 指向源订单（父子单结构）' do
      order
      extra_line_item

      result = described_class.call(order: order, groups: { 'g1' => [extra_line_item.id] })
      split_order = result.value.first

      expect(split_order.parent).to eq(order)
      expect(split_order.parent_order? ? true : split_order.child_order?).to be true
      expect(order.children).to include(split_order)
      expect(split_order.sibling_orders).to be_empty
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
      # extra_line_item 创建后 order.line_items 关联集合已缓存（不含 extra），先 reload 再重算使其计入 before_total
      order.line_items.reload
      PallasTrade::OrderUpdater.new(order).update
      before_total = order.reload.total

      result = described_class.call(order: order, groups: { 'g1' => [extra_line_item.id] })
      split_order = result.value.first

      expect(order.reload.total).to be < before_total
      expect(split_order.reload.total).to be > 0
    end
  end

  # PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 FR-027/028/029
  describe '跨店铺拆分（PRD-20260824）' do
    let(:target_store) { create(:store, code: 'order_splitter_target') }

    it 'AC-028: 目标店铺无该商品 → 返回 split_error 明确错误' do
      order
      extra_line_item
      result = described_class.call(
        order: order,
        groups: { 'g1' => { 'line_item_ids' => [extra_line_item.id], 'store_id' => target_store.prefixed_id } }
      )
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq(:split_error)
      expect(result.error.value[:message]).to include('目标店铺')
    end

    it 'AC-027/029: 目标店铺有该商品 → 子订单归属目标店铺，parent 指向原订单' do
      product_b = create(:product, store: target_store)
      variant_b = create(:variant, product: product_b)
      line_item_b = create(:line_item, order: order, variant: variant_b, price: 30)

      result = described_class.call(
        order: order,
        groups: { 'g1' => { 'line_item_ids' => [line_item_b.id], 'store_id' => target_store.prefixed_id } }
      )
      expect(result).to be_success
      split_order = result.value.first
      expect(split_order.store).to eq(target_store)
      expect(split_order.parent).to eq(order)
      expect(split_order.split_from).to eq(order)
    end
  end
end
