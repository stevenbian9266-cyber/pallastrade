# frozen_string_literal: true

require 'spec_helper'

# P0-0 回归安全网：Carts::Complete（standard flow）幂等性
# 锁定不变量：重复 complete 只完成订单一次；已完成的订单再次调用无副作用。
RSpec.describe PallasTrade::Carts::Complete, type: :service do
  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both', auto_capture: true) }

  # 标准流程订单：Carts::Submit 产物（state=pending, status=placed）
  def pending_standard_order(total: 100.0)
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0,
                                           line_items_price: total)
    order.update_columns(
      state: 'pending',
      status: 'placed',
      submitted_at: Time.current,
      completed_at: nil,
      payment_state: nil,
      payment_total: 0
    )
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  it 'completes a standard-flow order whose payment is already captured' do
    order = pending_standard_order
    create(:payment, order: order, payment_method: payment_method,
                     amount: order.total, state: 'completed')
    order.reload

    result = described_class.call(cart: order)

    expect(result).to be_success
    order.reload
    expect(order).to be_completed
    expect(order.state).to eq('paid')
    expect(order.status).to eq('placed')
    expect(order.payment_state).to eq('paid')
  end

  it 'is idempotent: a second complete call does not re-finalize or duplicate side effects' do
    order = pending_standard_order
    payment = create(:payment, order: order, payment_method: payment_method,
                               amount: order.total, state: 'completed')

    first = described_class.call(cart: order)
    expect(first).to be_success
    completed_at = order.reload.completed_at
    state_changes_before = order.state_changes.count

    second = described_class.call(cart: order)

    expect(second).to be_success
    order.reload
    expect(order.completed_at).to eq(completed_at)
    expect(order.payments.count).to eq(1)
    expect(order.state_changes.count).to eq(state_changes_before)
    expect(payment.reload.state).to eq('completed')
  end

  it 'refuses to complete an order with no valid captured payment (no_payment_found)' do
    order = pending_standard_order

    result = described_class.call(cart: order)

    expect(result).to be_failure
    expect(order.reload.completed_at).to be_nil
    expect(order.state).to eq('pending')
  end
end
