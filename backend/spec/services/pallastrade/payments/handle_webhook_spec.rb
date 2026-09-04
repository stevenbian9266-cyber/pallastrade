# frozen_string_literal: true

require 'spec_helper'

# P0-0 回归安全网：Payments::HandleWebhook（单订单路径）
# 锁定不变量：
#   - captured 事件 → 创建唯一 Payment → confirm! → session completed → 订单完成
#   - 同一 session 重复 webhook（幂等短路）不重复建 Payment / 不重复完成订单
#   - failed/canceled 事件 → session 终态；不创建 Payment
RSpec.describe PallasTrade::Payments::HandleWebhook, type: :service do
  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both', auto_capture: true) }

  # 标准流程订单（state=pending）：Carts::Submit 产物
  def pending_standard_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0, line_items_price: 100)
    order.update_columns(
      state: 'pending', status: 'placed', submitted_at: Time.current,
      completed_at: nil, payment_state: nil, payment_total: 0
    )
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def active_session(order)
    create(:bogus_payment_session, order: order, payment_method: payment_method,
                                   amount: order.total, status: 'pending')
  end

  it 'captured event creates exactly one Payment, completes the session and the order' do
    order = pending_standard_order
    session = active_session(order)

    result = described_class.call(payment_method: payment_method, action: :captured, payment_session: session)

    expect(result).to be_success
    expect(order.reload).to be_completed
    expect(order.state).to eq('paid')
    expect(session.reload).to be_completed
    expect(order.payments.count).to eq(1)
    payment = order.payments.first
    expect(payment).to be_completed
    # P0-1：Payment 必须显式关联 originating PaymentSession（正式 FK）
    expect(payment.payment_session_id).to eq(session.id)
  end

  it 'is idempotent: duplicate webhook for an already-completed session creates no second payment' do
    order = pending_standard_order
    session = active_session(order)

    described_class.call(payment_method: payment_method, action: :captured, payment_session: session)
    payments_after_first = order.reload.payments.count
    completed_at = order.reload.completed_at

    second = described_class.call(payment_method: payment_method, action: :captured, payment_session: session)

    expect(second).to be_success
    expect(order.reload.payments.count).to eq(payments_after_first)
    expect(order.payments.count).to eq(1)
    expect(order.completed_at).to eq(completed_at)
  end

  it 'failed event fails the session without creating a payment or completing the order' do
    order = pending_standard_order
    session = active_session(order)

    result = described_class.call(payment_method: payment_method, action: :failed, payment_session: session)

    expect(result).to be_success
    expect(session.reload).to be_failed
    expect(order.reload.payments).to be_empty
    expect(order.reload.completed_at).to be_nil
  end

  it 'canceled event cancels the session without creating a payment' do
    order = pending_standard_order
    session = active_session(order)

    result = described_class.call(payment_method: payment_method, action: :canceled, payment_session: session)

    expect(result).to be_success
    expect(session.reload).to be_canceled
    expect(order.reload.payments).to be_empty
  end

  it 'does not process a nil payment session' do
    result = described_class.call(payment_method: payment_method, action: :captured, payment_session: nil)

    expect(result).to be_success
  end
end
