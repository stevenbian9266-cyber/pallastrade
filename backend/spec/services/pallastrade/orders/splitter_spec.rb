# frozen_string_literal: true

require 'rails_helper'

# PRD-20260826-checkout-实施-p2-统一拆单引擎
# AC-001~008：Orders::Splitter 统一拆单引擎
RSpec.describe PallasTrade::Orders::Splitter do
  let(:store) { create(:store, code: 'splitter_test_store') }

  # 基础订单：3 个行项目（各 10）+ 1 个 shipment（默认 cost 100）
  let(:order) { create(:order_with_line_items, store: store, line_items_count: 3, line_items_price: 10) }

  describe '#call — 基础拆分（AC-001/003/005）' do
    it 'splits line items into child orders linked to the parent' do
      ids = order.line_items.map(&:id)

      result = described_class.call(order: order, groups: { a: [ids[0]], b: [ids[1], ids[2]] })

      expect(result.success?).to be true
      children = result.value
      expect(children.size).to eq(2)

      children.each do |child|
        expect(child.parent).to eq(order)
        expect(child.split_from).to eq(order)
        expect(child.store).to eq(order.store)
        expect(child.currency).to eq(order.currency)
      end

      expect(order.reload.children).to match_array(children)
      expect(children[0].line_items.pluck(:id)).to contain_exactly(ids[0])
      expect(children[1].line_items.pluck(:id)).to contain_exactly(ids[1], ids[2])
      expect(order.reload.line_items).to be_empty
    end

    it 'recomputes child totals (AC-005)' do
      ids = order.line_items.map(&:id)

      result = described_class.call(order: order, groups: { a: [ids[0]], b: [ids[1], ids[2]] })

      a, b = result.value
      expect(a.item_total).to eq(BigDecimal('10'))
      expect(b.item_total).to eq(BigDecimal('20'))
    end

    it 'keeps ungrouped line items on the source order' do
      ids = order.line_items.map(&:id)

      result = described_class.call(order: order, groups: { a: [ids[0]] })

      expect(result.success?).to be true
      expect(order.reload.line_items.pluck(:id)).to contain_exactly(ids[1], ids[2])
    end

    it 'moves line-item-level adjustments along with the line item (AC-003)' do
      li = order.line_items.first
      create(:adjustment, order: order, adjustable: li, amount: 5.0, label: 'Item fee')

      ids = order.line_items.map(&:id)
      result = described_class.call(order: order, groups: { a: [ids[0]], b: [ids[1], ids[2]] })

      moved = result.value.first.line_items.first.adjustments.first
      expect(moved).not_to be_nil
      expect(moved.order_id).to eq(result.value.first.id)
      expect(moved.adjustable_id).to eq(result.value.first.line_items.first.id)
    end
  end

  describe 'order-level adjustment apportionment（AC-004）' do
    it 'splits eligible non-tax order adjustments by line item amount ratio' do
      two = create(:order_with_line_items, store: store, line_items_count: 2, line_items_price: 10)
      promo_source = create(:promotion_action_create_adjustment)
      promo_adj = create(:adjustment, order: two, adjustable: two, source: promo_source, amount: -6.0, label: 'promo')
      promo_adj.update_columns(amount: -6.0, state: 'closed') # 模拟已确认折扣（冻结金额）

      ids = two.line_items.map(&:id)
      result = described_class.call(order: two, groups: { a: [ids[0]], b: [ids[1]] })

      a, b = result.value
      a_adj = a.adjustments.eligible.non_tax.first
      b_adj = b.adjustments.eligible.non_tax.first
      expect(a_adj.amount).to eq(BigDecimal('-3.0'))
      expect(b_adj.amount).to eq(BigDecimal('-3.0'))
      expect(a_adj.source).to eq(promo_source)
    end

    it 'conserves the total across split' do
      bare = create(:order, store: store)
      li1 = create(:line_item, order: bare, price: 10)
      li2 = create(:line_item, order: bare, price: 20)
      bare.reload
      promo = create(:promotion_action_create_adjustment)
      promo_adj = create(:adjustment, order: bare, adjustable: bare, source: promo, amount: -6.0, label: 'promo')
      promo_adj.update_columns(amount: -6.0, state: 'closed') # 模拟已确认折扣
      bare.update_with_updater!

      original_total = bare.reload.total
      ids = bare.line_items.map(&:id)
      result = described_class.call(order: bare, groups: { a: [ids[0]], b: [ids[1]] })
      children = result.value

      after_total = children.sum { |c| c.reload.total } + bare.reload.total
      expect(after_total).to eq(original_total)
    end
  end

  describe 'paid amount apportionment（AC-006）' do
    it 'creates a PaymentSplit per child by line item amount ratio' do
      two = create(:order_with_line_items, store: store, line_items_count: 2, line_items_price: 10)
      create(:payment, order: two, amount: 20, state: 'completed', response_code: "T-#{SecureRandom.hex(6)}")

      ids = two.line_items.map(&:id)
      result = described_class.call(order: two, groups: { a: [ids[0]], b: [ids[1]] })

      a, b = result.value
      expect(a.payment_splits.size).to eq(1)
      expect(a.payment_splits.first.captured_amount).to eq(BigDecimal('10'))
      expect(b.payment_splits.first.captured_amount).to eq(BigDecimal('10'))
      expect(a.payment_splits.first.payment_combination).to be_nil
    end
  end

  describe 'errors and idempotency（AC-002/007）' do
    it 'fails on empty groups' do
      result = described_class.call(order: order, groups: {})
      expect(result.failure?).to be true
    end

    it 'fails on a canceled order' do
      canceled = create(:order_with_line_items, store: store, line_items_count: 1)
      canceled.update_column(:state, 'canceled')

      ids = canceled.line_items.map(&:id)
      result = described_class.call(order: canceled, groups: { a: [ids[0]] })
      expect(result.failure?).to be true
    end

    it 'does not re-split an already split order（AC-007）' do
      ids = order.line_items.map(&:id)
      first = described_class.call(order: order, groups: { a: [ids[0]], b: [ids[1], ids[2]] })
      expect(first.success?).to be true

      second = described_class.call(order: order, groups: { a: [ids[0]], b: [ids[1], ids[2]] })
      expect(second.failure?).to be true
      expect(order.reload.children.size).to eq(2)
    end
  end

  describe 'event（AC-008）' do
    it 'publishes order.splitted with child order ids' do
      ids = order.line_items.map(&:id)
      expect(order).to receive(:publish_event)
        .with('order.splitted', hash_including(:child_order_ids))
        .and_call_original

      described_class.call(order: order, groups: { a: [ids[0]], b: [ids[1], ids[2]] })
    end
  end
end
