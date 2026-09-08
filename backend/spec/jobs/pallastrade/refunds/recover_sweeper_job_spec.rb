# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-6 —— Refunds::RecoverSweeperJob 保守自动扫描
# requested stale（attempts<MAX）→ enqueue RecoverJob；capped 不再 enqueue；processing stale →
# enqueue（Recover 收敛 ambiguous）；ambiguous/manual/failed 仅计数（不自动 enqueue）。
RSpec.describe PallasTrade::Refunds::RecoverSweeperJob, type: :job do
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

  it 'requested stale（attempts<MAX）→ enqueue RecoverJob；capped 不 enqueue；processing stale → enqueue' do
    stale = refund_in('requested', updated_minutes_ago: 90)
    capped = refund_in('requested', updated_minutes_ago: 90, attempts: 5)
    processing = refund_in('processing', updated_minutes_ago: 60 * 8)
    fresh = refund_in('requested', updated_minutes_ago: 5)

    enqueued = []
    allow(PallasTrade::Refunds::RecoverJob).to receive(:perform_later) { |id| enqueued << id }

    described_class.perform_now(requested_hours: 1, processing_hours: 6)

    expect(enqueued).to contain_exactly(stale.id, processing.id)
    expect(enqueued).not_to include(capped.id, fresh.id)
  end

  it 'ambiguous/manual_review/failed 只计数不 enqueue（warn 供人工）' do
    refund_in('ambiguous', updated_minutes_ago: 60 * 8)
    refund_in('manual_review', updated_minutes_ago: 60 * 8)
    refund_in('failed', updated_minutes_ago: 60 * 8)

    allow(PallasTrade::Refunds::RecoverJob).to receive(:perform_later)
    allow(Rails.logger).to receive(:warn)

    described_class.perform_now

    expect(Rails.logger).to have_received(:warn).with(a_string_including('human attention'))
  end
end
