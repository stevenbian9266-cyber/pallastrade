# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-6 —— Refunds::Recover 确定性收敛
# requested stale→幂等 Execute 重跑（attempts 封顶）；processing stale→mark_ambiguous（超时，
# REV-INV-04 不自动重退）；ambiguous/failed/manual_review/fresh 不动。
RSpec.describe PallasTrade::Refunds::Recover, type: :service do
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

  def refund_in(state, updated_minutes_ago:, attempts: 0)
    r = create(:refund, payment: payment, amount: 5, reason: reason,
                        state: state, transaction_id: nil, attempt_count: attempts)
    r.update_column(:updated_at, updated_minutes_ago.minutes.ago)
    r
  end

  it 'requested stale → enqueue ExecuteJob（幂等重跑，资金执行只经 ExecuteJob）' do
    refund = refund_in('requested', updated_minutes_ago: 90)
    expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(refund.id).once

    result = described_class.call(refund: refund)

    expect(result.success?).to be(true)
    # async：仍为 requested（ExecuteJob 异步执行；Execute 幂等 claim + 稳定 idempotency key）
    expect(refund.reload).to be_requested
  end

  it 'requested fresh（未 stale）→ 不动' do
    refund = refund_in('requested', updated_minutes_ago: 5)

    described_class.call(refund: refund)

    expect(refund.reload).to be_requested
  end

  it 'requested stale 但 attempts 达上限 → 不再自动重跑' do
    refund = refund_in('requested', updated_minutes_ago: 90, attempts: 5)

    described_class.call(refund: refund)

    expect(refund.reload).to be_requested
  end

  it 'processing stale → mark_ambiguous（超时收敛，不自动重退）' do
    refund = refund_in('processing', updated_minutes_ago: 60 * 8)

    described_class.call(refund: refund, processing_hours: 6)

    expect(refund.reload).to be_ambiguous
    expect(refund.last_error_code).to eq('RECOVERY_TIMEOUT')
  end

  it 'ambiguous / failed / manual_review → 不动（人工/后续收敛）' do
    %w[ambiguous failed manual_review].each do |state|
      refund = refund_in(state, updated_minutes_ago: 60 * 8)
      described_class.call(refund: refund)
      expect(refund.reload.state).to eq(state)
    end
  end
end
