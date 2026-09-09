# frozen_string_literal: true

require 'rails_helper'

# PRD-20260909-payments-孤儿退款补记-backfill-refunds-backfillproviderrefund-rake-dry-run- (REV-P6-8m)
# AC-R68M-01~04: Refunds::BackfillProviderRefund —— 孤儿补记（补记即终态；绝不二次 PSP）
RSpec.describe PallasTrade::Refunds::BackfillProviderRefund, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'complete', completed_at: Time.current,
                   item_total: 100, total: 100, payment_state: 'paid')
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  def backfill(provider_id: 're_provider_1', amount: 5.0, currency: 'USD')
    described_class.call(payment: payment, provider_id: provider_id, amount: amount,
                         currency: currency, actor: 'spec_operator')
  end

  it 'AC-R68M-01: 孤儿补记 → Refund 行 succeeded + transaction_id + metadata + Audit；绝不调 PSP/ExecuteJob' do
    allow(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later) # 不应被调用

    expect { backfill }
      .to change(PallasTrade::Refund, :count).by(1)
      .and change { PallasTrade::AuditLog.where(action: 'refund_orphan_backfill').count }.by(1)

    refund = PallasTrade::Refund.find_by(transaction_id: 're_provider_1')
    expect(refund).to be_present
    expect(refund.payment).to eq(payment)
    expect(refund.state).to eq('succeeded')
    expect(refund.metadata['backfilled_orphan']).to be(true)
    expect(refund.reason.name).to eq(PallasTrade::RefundReason::ORPHAN_BACKFILL_REASON)
    expect(PallasTrade::AuditLog.where(action: 'refund_orphan_backfill').last.actor_label).to eq('spec_operator')
    expect(PallasTrade::Refunds::ExecuteJob).not_to have_received(:perform_later)
  end

  it 'AC-R68M-02: 同 payment+provider_id 重复 → noop 不重复建行' do
    first = backfill
    expect(first.value[:status]).to eq('backfilled')

    expect { backfill }
      .not_to change(PallasTrade::Refund, :count)

    second = backfill
    expect(second.value[:status]).to eq('already_backfilled')
  end

  it 'AC-R68M-03: amount 不可证明（nil/0）→ skipped 不建行' do
    expect { backfill(amount: nil) }.not_to change(PallasTrade::Refund, :count)
    result = backfill(amount: nil)
    expect(result.value[:status]).to eq('skipped')
    expect(result.value[:reason]).to eq('orphan_amount_unavailable')

    expect { backfill(amount: 0) }.not_to change(PallasTrade::Refund, :count)
  end

  it 'AC-R68M-03: payment 缺失 → failure' do
    result = described_class.call(payment: nil, provider_id: 're_x', amount: 5)
    expect(result.failure?).to be(true)
  end

  it 'AC-R68M-04: RefundReason.orphan_backfill_reason 存在且不可变' do
    reason = PallasTrade::RefundReason.orphan_backfill_reason
    expect(reason.name).to eq('Provider Refund Backfill')
    expect(reason.mutable).to be(false)
    expect(PallasTrade::RefundReason.orphan_backfill_reason).to eq(reason)
  end
end
