# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-2 AC-R62-01/02 —— Refunds::Request（durable requested + enqueue，绝不调 PSP）
# 注：应用使用 Sidekiq adapter（非 ActiveJob test adapter）→ 用 perform_later mock 断言入队。
RSpec.describe PallasTrade::Refunds::Request, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'paid')
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end
  let(:reason) { create(:refund_reason) }

  it 'creates durable requested refund and enqueues ExecuteJob without calling provider' do
    expect_any_instance_of(PallasTrade::Gateway::Bogus).not_to receive(:credit)
    expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once

    result = nil
    expect { result = described_class.call(payment: payment, amount: 60, reason: reason) }
      .to change(PallasTrade::Refund, :count).by(1)
    expect(result.success?).to be(true)

    refund = PallasTrade::Refund.last
    expect(refund).to be_requested
    expect(refund.requested_at).to be_present
    expect(refund.payment).to eq(payment)
    expect(refund.reason).to eq(reason)
  end

  it 'does NOT enqueue nor persist when create validation fails (over capacity, AC-6002)' do
    create(:refund, payment: payment, amount: 80, transaction_id: 're_taken') # succeeded
    expect(PallasTrade::Refunds::ExecuteJob).not_to receive(:perform_later)

    result = described_class.call(payment: payment, amount: 60, reason: reason)
    expect(result.success?).to be(false)
    expect(PallasTrade::Refund.count).to eq(1)
  end

  it 'freezes ownership when provable (commerce_transaction/target_order)' do
    txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100)
    expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once

    result = described_class.call(
      payment: payment, amount: 30, reason: reason,
      commerce_transaction: txn, target_order: order
    )
    expect(result.success?).to be(true)

    refund = PallasTrade::Refund.last
    expect(refund.commerce_transaction).to eq(txn)
    expect(refund.target_order).to eq(order)
  end
end
