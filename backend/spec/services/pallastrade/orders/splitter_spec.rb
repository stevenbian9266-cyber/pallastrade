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

    # PRD-20260824 FR-031/032
    it 'AC-031: 拆出的子订单获得独立 shipment（可单独触发发货）' do
      order
      target = order.line_items.first
      expect(target.inventory_units).not_to be_empty

      result = described_class.call(order: order, groups: { 'g1' => [target.id] })
      split_order = result.value.first

      expect(split_order.shipments.size).to eq(1)
      expect(split_order.shipments.first.stock_location).to eq(order.shipments.first.stock_location)
      expect(split_order.inventory_units).not_to be_empty
      expect(split_order.inventory_units.first.shipment).to eq(split_order.shipments.first)
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

  # PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 FR-039/AC-039
  describe '促销优惠拆单分摊（PRD-20260824）' do
    it 'AC-039: 订单级促销按行项目金额比例分摊到子订单，总额守恒' do
      promotion = create(:promotion, code: 'PCT10')
      calculator = PallasTrade::Calculator::FlatPercentItemTotal.new
      calculator.preferred_flat_percent = 10
      PallasTrade::Promotion::Actions::CreateAdjustment.create!(calculator: calculator, promotion: promotion)

      order = create(:order_with_line_items, store: store, user: user, currency: 'USD', shipment_cost: 0)
      extra = create(:line_item, order: order, price: 50)
      order.line_items.reload
      PallasTrade::OrderUpdater.new(order).update
      promotion.activate(order: order)
      order.reload
      PallasTrade::OrderUpdater.new(order).update

      before_promo = order.adjustments.promotion.eligible.sum(:amount)
      expect(before_promo).to be < 0

      result = described_class.call(order: order, groups: { 'g1' => [extra.id] })
      expect(result).to be_success
      child = result.value.first

      # 子订单获得订单级促销（负值）
      child_promo = child.adjustments.promotion.eligible.sum(:amount)
      expect(child_promo).to be < 0

      # 总额守恒：父订单 promo + 子订单 promo == 拆前 promo
      parent_promo = order.reload.adjustments.promotion.eligible.sum(:amount)
      expect((parent_promo + child_promo).round(2)).to eq(before_promo.round(2))
    end

    it 'AC-039: 子订单 promo 约等于按行项目金额比例分摊的金额' do
      promotion = create(:promotion, code: 'PCT10B')
      calculator = PallasTrade::Calculator::FlatPercentItemTotal.new
      calculator.preferred_flat_percent = 10
      PallasTrade::Promotion::Actions::CreateAdjustment.create!(calculator: calculator, promotion: promotion)

      order = create(:order_with_line_items, store: store, user: user, currency: 'USD', shipment_cost: 0)
      extra = create(:line_item, order: order, price: 50)
      order.line_items.reload
      PallasTrade::OrderUpdater.new(order).update
      promotion.activate(order: order)
      order.reload
      PallasTrade::OrderUpdater.new(order).update

      result = described_class.call(order: order, groups: { 'g1' => [extra.id] })
      child = result.value.first

      # 子订单金额 50 / 总额 60 → 10% 折扣 6 中分摊 5
      child_promo = child.adjustments.promotion.eligible.sum(:amount)
      expect(child_promo).to be_within(0.01).of(-5.0)
    end
  end

  # PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 FR-038/AC-038
  describe '税费运费拆单分摊（PRD-20260824）' do
    it 'AC-038: 拆单后运费按行项目金额比例分摊，总额守恒' do
      order = create(:order_with_line_items, store: store, user: user, currency: 'USD', shipment_cost: 10)
      # 拆走第一个 line_item（10 元，有 inventory_units）；第二个（50 元）留在父订单
      extra = create(:line_item, order: order, price: 50)
      order.line_items.reload
      PallasTrade::OrderUpdater.new(order).update
      before_total = order.reload.total

      target = order.line_items.find { |li| li.price.to_d == 10 }
      result = described_class.call(order: order, groups: { 'g1' => [target.id] })
      expect(result).to be_success
      child = result.value.first

      # 子订单获得 shipment（运费分摊 10 * 10/60 ≈ 1.67）
      expect(child.shipments.size).to eq(1)
      child_cost = child.shipments.first.cost.to_d
      parent_cost = order.reload.shipments.first.cost.to_d
      expect((child_cost + parent_cost).round(2)).to eq(10.0)

      # 总额守恒（商品 + 运费）
      expect((child.reload.total + order.reload.total).round(2)).to eq(before_total.round(2))
    end
  end
end
