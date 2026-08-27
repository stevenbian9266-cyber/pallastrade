# frozen_string_literal: true

require 'rails_helper'

# PRD-20260826-payments-实施-p1-数据模型与语义方法
# AC-001/002/006：Order parent/children/split_from 关联 + 语义方法 + root 防环
RSpec.describe PallasTrade::Order, type: :model do
  let!(:store) { create(:store, code: 'order_parent_store') }

  describe 'parent / children associations (AC-001)' do
    it 'persists parent_id and links parent/children' do
      parent = create(:order, store: store)
      child = create(:order, store: store, parent: parent)

      expect(parent.reload.children).to include(child)
      expect(child.parent).to eq(parent)
      expect(child.parent_id).to eq(parent.id)
    end

    it 'nullifies parent link when parent is destroyed' do
      parent = create(:order, store: store)
      child = create(:order, store: store, parent: parent)

      parent.destroy!
      expect(child.reload.parent_id).to be_nil
    end
  end

  describe 'split_from associations (AC-002)' do
    it 'persists split_from_id and links split_orders' do
      source = create(:order, store: store)
      child = create(:order, store: store, split_from: source)

      expect(source.reload.split_orders).to include(child)
      expect(child.split_from).to eq(source)
      expect(child.split_from_id).to eq(source.id)
    end
  end

  describe 'parent/child semantics (AC-006)' do
    it 'treats a non-split order as single' do
      order = create(:order, store: store)
      expect(order).to be_single_order
      expect(order).not_to be_parent_order
      expect(order).not_to be_child_order
    end

    it 'treats an order with children as parent' do
      parent = create(:order, store: store)
      create(:order, store: store, parent: parent)

      expect(parent).to be_parent_order
      expect(parent).not_to be_child_order
      expect(parent).not_to be_single_order
    end

    it 'treats an order with a parent as child' do
      parent = create(:order, store: store)
      child = create(:order, store: store, parent: parent)

      expect(child).to be_child_order
      expect(child).not_to be_parent_order
      expect(child).not_to be_single_order
    end

    it 'returns sibling orders under the same parent' do
      parent = create(:order, store: store)
      child1 = create(:order, store: store, parent: parent)
      child2 = create(:order, store: store, parent: parent)

      expect(child1.sibling_orders).to contain_exactly(child2)
      expect(child2.sibling_orders).to contain_exactly(child1)
      expect(parent.sibling_orders).to be_empty
    end

    it 'walks the parent chain to the root without infinite loop' do
      root = create(:order, store: store)
      mid = create(:order, store: store, parent: root)
      leaf = create(:order, store: store, parent: mid)

      expect(leaf.root_order).to eq(root)
      expect(mid.root_order).to eq(root)
      expect(root.root_order).to eq(root)
    end

    it 'is safe against a corrupt self-referencing cycle' do
      order = create(:order, store: store)
      order.update!(parent_id: order.id)

      expect { order.root_order }.not_to raise_error
      expect(order.root_order).to eq(order)
    end
  end

  # PRD-20260827-payments P3 AC-001~007：父订单聚合派生（金额/支付/发货状态）
  describe 'P3 combined aggregates (AC-001~007)' do
    # order_ready_to_ship: line_item(10) + shipment(100) = total 110, completed payment 110, ready shipment
    let!(:parent)  { create(:order_ready_to_ship, store: store) }
    let!(:child_a) { create(:order_ready_to_ship, store: store, parent: parent) }
    let!(:child_b) { create(:order_ready_to_ship, store: store, parent: parent) }

    it 'AC-001 combined_total aggregates children recursively' do
      expect(parent.combined_total).to eq(330) # 110 * 3
      # 无 children → 回退 own total
      expect(child_a.combined_total).to eq(110)
    end

    it 'AC-002 combined_payment_total aggregates children payments' do
      expect(parent.combined_payment_total).to eq(330)
      expect(child_a.combined_payment_total).to eq(110)
    end

    it 'AC-003 combined_outstanding_balance = combined_total - (paid + reimbursed)' do
      expect(parent.combined_outstanding_balance).to eq(0)
      # 少付一个子订单 → 正余额（payment_total 是 DB 列，直接模拟 + 刷新 children 缓存）
      child_a.update_column(:payment_total, 50)
      parent.children.reload
      expect(parent.combined_outstanding_balance).to eq(60)
    end

    it 'AC-004 combined_amount_due caps at zero' do
      expect(parent.combined_amount_due).to eq(0)
      child_a.update_column(:payment_total, 0)
      parent.children.reload
      expect(parent.combined_amount_due).to eq(110)
    end

    it 'AC-005 combined_shipment_state aggregates to partial when mixed' do
      expect(parent.combined_shipment_state).to eq('ready')
      # shipment_state 是 DB 列，直接模拟子订单已发货 + 刷新 children 缓存
      child_b.update_column(:shipment_state, 'shipped')
      parent.children.reload
      expect(child_b.combined_shipment_state).to eq('shipped')
      expect(parent.combined_shipment_state).to eq('partial')
    end

    it 'AC-006 combined_payment_state reflects aggregate balance' do
      expect(parent.combined_payment_state).to eq('paid')

      child_a.update_column(:payment_total, 50)
      parent.children.reload
      expect(parent.combined_payment_state).to eq('balance_due')

      child_a.update_column(:payment_total, 120)
      parent.children.reload
      expect(parent.combined_payment_state).to eq('credit_owed')
    end

    it 'AC-007 no children → combined_* fall back to own values' do
      single = create(:order_ready_to_ship, store: store)
      expect(single.combined_total).to eq(single.total)
      expect(single.combined_payment_total).to eq(single.payment_total)
      expect(single.combined_outstanding_balance).to eq(single.outstanding_balance)
      expect(single.combined_amount_due).to eq(single.amount_due)
      expect(single.combined_shipment_state).to eq('ready')
      expect(single.combined_payment_state).to eq('paid')
    end

    it 'AC-008 effective_payment_total uses PaymentSplit when present, else payment_total' do
      # 无 split → payment_total
      expect(child_a.effective_payment_total).to eq(110)

      # 有 split → captured - refunded（复用已有 completed payment，避免重复建 store）
      payment = parent.payments.completed.first
      create(:payment_split, order: parent, payment_combination: nil, payment: payment,
                             captured_amount: 80, refunded_amount: 10)
      expect(parent.effective_payment_total).to eq(70)
    end
  end
end
