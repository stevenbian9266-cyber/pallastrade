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
end
