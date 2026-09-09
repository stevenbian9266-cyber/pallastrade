# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-4 AC-R64-01~06 —— Cancellation Orchestration
# Orders::Cancel 升级为 Cancellation Orchestrator：PAID 默认显式 durable Refund(requested)
# （事务内建行 enqueue:false → 提交后 ExecuteJob），refund_payments=false 真正生效；
# Order#after_cancel 不再隐式 cancel PSP completed payment（RISK-REV-04 / 源 §30/§59/RV-R06/R07）。
# 注：应用 Sidekiq adapter → 用 ExecuteJob.perform_later mock 断言入队。
RSpec.describe PallasTrade::Orders::Cancel, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def pending_order
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 100, total: 100, payment_state: 'balance_due',
                   currency: store.default_currency, email: 'buyer@example.com')
  end

  def paid_order
    order = pending_order
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
    order
  end

  it 'AC-R64-01: UNPAID cancel → order canceled、无 Refund、不 enqueue（RV-R06）' do
    order = pending_order
    expect(PallasTrade::Refunds::ExecuteJob).not_to receive(:perform_later)

    result = described_class.call(order: order, reason: 'customer')

    expect(result.success?).to be(true)
    expect(order.reload.state).to eq('canceled')
    expect(order.cancellations.last.state).to eq('applied') # REV-P6-8j：durable intent applied
    expect(PallasTrade::Refund.where(payment_id: order.payments.pluck(:id))).to be_empty
  end

  it 'AC-R64-02/AC-R64-06: PAID cancel（auto 默认）→ durable Refund(requested, full credit) + canceled，PSP payment 不再被 after_cancel cancel（RV-R07）' do
    order = paid_order
    payment = PallasTrade::Payment.find_by!(order_id: order.id)
    expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once

    result = described_class.call(order: order, reason: 'staff')

    expect(result.success?).to be(true)
    expect(order.reload.state).to eq('canceled')
    expect(order.cancellations.last.refund_payments).to be(true) # auto → resolved true（audit）
    expect(order.cancellations.last.state).to eq('applied') # REV-P6-8j：durable intent applied

    refund = PallasTrade::Refund.last
    expect(refund.state).to eq('requested')
    expect(refund.amount.to_f).to eq(100.0)
    expect(refund.payment).to eq(payment)
    expect(refund.reason.name).to eq(PallasTrade::RefundReason::ORDER_CANCELED_REASON)

    # after_cancel 不再隐式 cancel PSP completed payment（payment 保持 completed，退款由 requested 行承担）
    expect(payment.reload).to be_completed
    # 事务内建行 + 提交后单次入队 → 只有 1 个 requested refund
    expect(PallasTrade::Refund.where(payment_id: payment.id, state: 'requested').count).to eq(1)
  end

  it 'AC-R64-03: PAID cancel + refund_payments=false → 无 Refund、payment 保持 completed、order canceled（§35 合法态）' do
    order = paid_order
    payment = PallasTrade::Payment.find_by!(order_id: order.id)
    expect(PallasTrade::Refunds::ExecuteJob).not_to receive(:perform_later)

    result = described_class.call(order: order, reason: 'staff', refund_payments: false)

    expect(result.success?).to be(true)
    expect(order.reload.state).to eq('canceled')
    expect(order.cancellations.last.refund_payments).to be(false)
    expect(payment.reload).to be_completed
    expect(PallasTrade::Refund.where(payment_id: payment.id)).to be_empty
  end

  it 'AC-R64-04: PAID cancel + refund_amount < credit → requested Refund.amount = 指定值' do
    order = paid_order
    expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once

    result = described_class.call(order: order, reason: 'staff', refund_amount: 40)

    expect(result.success?).to be(true)
    refund = PallasTrade::Refund.last
    expect(refund.state).to eq('requested')
    expect(refund.amount.to_f).to eq(40.0)
  end

  it 'AC-R64-04(边界): refund_amount 仅支持单笔可退 PSP 支付——多笔时 failure 且不取消' do
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 200, total: 200, payment_state: 'balance_due',
                           currency: store.default_currency, email: 'buyer@example.com')
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
    expect(PallasTrade::Refunds::ExecuteJob).not_to receive(:perform_later)

    result = described_class.call(order: order, reason: 'staff', refund_amount: 40)

    expect(result.success?).to be(false)
    expect(order.reload.state).not_to eq('canceled')
    expect(PallasTrade::Refund.count).to eq(0)
  end

  it 'AC-R64-05: 重复取消 → 不产生第二笔 Refund（幂等）' do
    order = paid_order
    expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once

    expect(described_class.call(order: order, reason: 'staff').success?).to be(true)
    expect(PallasTrade::Refund.count).to eq(1)

    expect(PallasTrade::Refunds::ExecuteJob).not_to receive(:perform_later)
    second = described_class.call(order: order.reload, reason: 'staff')
    expect(second.success?).to be(false) # allow_cancel?=false → InvalidTransition → failure
    expect(PallasTrade::Refund.count).to eq(1)
  end
end
