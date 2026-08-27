# frozen_string_literal: true

require 'rails_helper'

# PRD-20260827-payments-实施-p4 合并支付载体
# AC-001/002/003：PaymentCombinations::Create 校验 / 服务端金额 / 组合+splits+session
RSpec.describe PallasTrade::Payments::PaymentCombinations::Create, type: :service do
  let!(:store) { create(:store, code: 'pcom_create_store') }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }

  # order_with_line_items：含地址/shipment 且自动跑 OrderUpdater；固定运费 0 并移除
  # selected_shipping_rate，避免 complete 时 update_amounts 用默认运费重算漂移 total
  def unpaid_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0)
    order.shipments.each do |s|
      s.shipping_rates.destroy_all
      s.add_shipping_method(create(:free_shipping_method), true)
    end
    # 推进到 payment 状态触发 create_tax_charge! 固化含税金额，再重置回 cart 供 Complete 完成
    order.next until order.payment? || order.complete? || order.errors.any?
    order.update_columns(state: 'cart', completed_at: nil)
    order.line_items.reload
    PallasTrade::OrderUpdater.new(order).update
    order.reload
    order
  end

  let(:order1) { unpaid_order } # total = amount_due（含税）
  let(:order2) { unpaid_order }
  let(:combined_amount) { (order1.amount_due + order2.amount_due).to_f }

  def call(orders:, store: self.store, customer: user)
    described_class.call(
      store: store, customer: customer, orders: orders, payment_method: payment_method
    )
  end

  describe '#call' do
    it 'AC-003 creates combination + per-order splits + session on primary order' do
      result = call(orders: [order1, order2])

      expect(result.success?).to be true
      combination = result.value
      expect(combination).to be_persisted
      expect(combination.status).to eq('processing')
      expect(combination.currency).to eq('USD')
      expect(combination.payment_splits.count).to eq(2)
      expect(combination.orders).to contain_exactly(order1, order2)

      session = order1.reload.payment_sessions.last
      expect(session).to be_present
      expect(session.payment_combination).to eq(combination)
      expect(session.amount).to eq(combined_amount)
    end

    it 'AC-002 computes amount server-side as the sum of unpaid amount_due' do
      result = call(orders: [order1, order2])
      expect(result.value.amount).to eq(combined_amount)
    end

    it 'AC-002 excludes paid orders from the amount and membership' do
      paid = unpaid_order
      paid.update_column(:payment_total, paid.total) # outstanding 0

      result = call(orders: [order1, paid])
      expect(result.success?).to be true
      expect(result.value.amount).to eq(order1.amount_due.to_f) # only order1
      expect(result.value.orders).to contain_exactly(order1)
    end

    it 'AC-001 rejects cross-store orders' do
      other = create(:store, code: 'pcom_other_store')
      order3 = create(:order_with_line_items, store: other, user: user, shipment_cost: 0)

      result = call(orders: [order1, order3])
      expect(result.failure?).to be true
      expect(result.error.to_s).to include('same store')
    end

    it 'AC-001 rejects orders with no unpaid member' do
      result = call(orders: [])
      expect(result.failure?).to be true

      all_paid = unpaid_order
      all_paid.update_column(:payment_total, all_paid.total)
      result = call(orders: [all_paid])
      expect(result.failure?).to be true
      expect(result.error.to_s).to include('No unpaid orders')
    end
  end
end
