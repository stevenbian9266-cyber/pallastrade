# frozen_string_literal: true

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 FR-041 / AC-041
# 订单取消联动：父取消 → 子订单联动处理；仅取消指定子订单；已支付走退款
require 'rails_helper'

RSpec.describe PallasTrade::Orders::Cancel, type: :service do
  let(:store) { create(:store, code: 'cancel_test') }
  let(:user) { create(:user) }

  def build_parent_with_child
    parent = create(:order_with_line_items, store: store, user: user, currency: 'USD')
    extra = create(:line_item, order: parent, price: 50)
    result = PallasTrade::Orders::Splitter.call(order: parent, groups: { 'g1' => [extra.id] })
    child = result.value.first
    [parent, child]
  end

  def complete_order(order)
    order.update_columns(completed_at: Time.current, state: 'complete')
  end

  describe '#call' do
    it 'AC-041: 取消父订单 → 联动取消其全部子订单（各自记录取消原因）' do
      parent, child = build_parent_with_child
      complete_order(parent)
      complete_order(child)

      result = described_class.call(order: parent, reason: 'customer')

      expect(result).to be_success
      expect(parent.reload.canceled_at).to be_present
      expect(parent.reload.cancellations.count).to eq(1)
      expect(child.reload.canceled_at).to be_present
      expect(child.reload.cancellations.count).to eq(1)
      expect(child.reload.cancellations.first.reason).to eq('customer')
    end

    it 'AC-041: cascade: false 仅取消指定子订单，父订单与兄弟不受影响' do
      parent, child = build_parent_with_child
      complete_order(parent)
      complete_order(child)

      result = described_class.call(order: child, reason: 'customer', cascade: false)

      expect(result).to be_success
      expect(child.reload.canceled_at).to be_present
      expect(parent.reload.canceled_at).to be_nil
    end

    it 'AC-041: refund_payments 时父子订单各自退款（completed payments 被取消）' do
      parent, child = build_parent_with_child
      complete_order(parent)
      complete_order(child)
      create(:payment, order: parent, state: 'completed', amount: parent.total)
      create(:payment, order: child, state: 'completed', amount: child.total)

      result = described_class.call(order: parent, reason: 'customer', refund_payments: true)

      expect(result).to be_success
      expect(parent.reload.payments.completed).to be_empty
      expect(child.reload.payments.completed).to be_empty
    end
  end
end
