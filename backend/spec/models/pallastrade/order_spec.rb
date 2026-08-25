require 'rails_helper'

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化
# AC-005/006/007/008 — 父子单结构（Order#parent_id 自引用，父=子语义）
RSpec.describe PallasTrade::Order, type: :model do
  let(:store) { PallasTrade::Store.default }
  let(:user) { create(:user) }

  describe '父子单结构 (PRD-20260824)' do
    it 'AC-005: parent_id 可空自引用 FK，父/子订单 ID 各自唯一' do
      order = create(:order_with_line_items, store: store, user: user)
      expect(order.parent_id).to be_nil
      expect(order).to respond_to(:parent)
      expect(order).to respond_to(:children)
      expect(order.id).to be_present
      expect(order.number).to be_present
    end

    it 'AC-006: 拆单后父订单保留，子订单 parent_id 指向父；一个父订单对应多个子订单' do
      parent = create(:order_with_line_items, store: store, user: user)
      child1 = create(:order_with_line_items, store: store, user: user, parent: parent)
      child2 = create(:order_with_line_items, store: store, user: user, parent: parent)

      expect(parent.children.reload).to contain_exactly(child1, child2)
      expect(child1.parent).to eq(parent)
      expect(child2.parent).to eq(parent)
      expect(parent.parent_order?).to be true
      expect(child1.child_order?).to be true
      expect(child2.child_order?).to be true
    end

    it 'AC-007: 未拆单单笔订单 parent_id=nil 且无子订单 → 既是父订单也是子订单（父=子）' do
      order = create(:order_with_line_items, store: store, user: user)
      expect(order.parent_id).to be_nil
      expect(order.parent_order?).to be false
      expect(order.child_order?).to be false
      expect(order.single_order?).to be true
    end

    it 'AC-008: split_from_id 保留为展示用来源引用' do
      source = create(:order_with_line_items, store: store, user: user)
      split = create(:order_with_line_items, store: store, user: user, split_from: source)
      expect(split.split_from).to eq(source)
      expect(source.split_orders).to include(split)
    end

    it 'sibling_orders 返回同一父订单下的其它子订单' do
      parent = create(:order_with_line_items, store: store, user: user)
      child1 = create(:order_with_line_items, store: store, user: user, parent: parent)
      child2 = create(:order_with_line_items, store: store, user: user, parent: parent)

      expect(child1.sibling_orders.reload).to contain_exactly(child2)
      expect(child2.sibling_orders.reload).to contain_exactly(child1)
    end
  end

  # Bugfix 2026-08-25: PaymentSession checkout 创建的订单在未完成支付前
  # payment_state 为 nil（从未运行 OrderUpdater#update_payment_state）。
  # 旧 scope 的 `where.not(payment_state: 'paid')` 在 SQL 层对 NULL 不成立，
  # 导致此类"待付款"订单被排除出合并支付列表（订单页无付款入口）。
  describe 'unpaid_for_combined_payment (bugfix 2026-08-25)' do
    it '包含 payment_state 为 NULL 的 placed 订单（无 payment 记录但欠款）' do
      order = create(
        :order_with_line_items,
        store: store,
        user: user,
        status: 'placed',
        payment_state: nil,
        canceled_at: nil,
      )
      expect(described_class.unpaid_for_combined_payment).to include(order)
    end

    it '包含 balance_due 的 placed 订单' do
      order = create(
        :order_with_line_items,
        store: store,
        user: user,
        status: 'placed',
        payment_state: 'balance_due',
        canceled_at: nil,
      )
      expect(described_class.unpaid_for_combined_payment).to include(order)
    end

    it '排除 paid / credit_owed / canceled / draft 订单' do
      paid = create(:order_with_line_items, store: store, user: user, status: 'placed', payment_state: 'paid')
      credit = create(:order_with_line_items, store: store, user: user, status: 'placed', payment_state: 'credit_owed')
      canceled = create(
        :order_with_line_items,
        store: store,
        user: user,
        status: 'placed',
        payment_state: 'balance_due',
        canceled_at: Time.current,
      )
      draft = create(:order_with_line_items, store: store, user: user, status: 'draft', payment_state: nil)

      result = described_class.unpaid_for_combined_payment
      expect(result).not_to include(paid)
      expect(result).not_to include(credit)
      expect(result).not_to include(canceled)
      expect(result).not_to include(draft)
    end
  end
end
