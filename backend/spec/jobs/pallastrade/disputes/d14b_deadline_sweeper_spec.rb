# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('config/sidekiq_schedule')

ActiveJob::Base.queue_adapter = :test

# PRD-20260916-payments-d14b-dispute-deadlines（切片2，job）
#   AC-007 ← FR-003：sweeper 摘要保留既有字段 + 追加分档指标；既有事件发布不变；分档台账随之落库
RSpec.describe PallasTrade::Disputes::DeadlineSweeperJob, type: :job do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_price: 50, shipment_cost: 0).tap do |o|
      o.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)
    end
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: order.total, state: 'completed',
                     response_code: 'pi_d14b_sweep', source: nil, skip_source_requirement: true)
  end
  let(:txn) do
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: order.total)
  end

  def make_dispute(state: 'needs_response', due_at: nil, reference: nil)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: reference || "dp_d14bs_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd', store: store,
      private_metadata: { 'provider_status' => 'needs_response' },
      evidence_due_at: due_at,
      commerce_transaction: txn, payment: payment, order: order
    )
  end

  before do
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  # AC-007
  it 'keeps the legacy summary keys and adds the tier metrics while recording the ledger' do
    soon = make_dispute(due_at: Time.current + 40.hours, reference: 'dp_d14bs_soon')
    late = make_dispute(due_at: Time.current - 2.hours, reference: 'dp_d14bs_late')

    summary = described_class.perform_now

    expect(summary).to include(:published, :failed, :overdue, :due_soon, :window_hours, :scanned_at)
    expect(summary[:overdue]).to eq(1)
    expect(summary[:due_soon]).to eq(1)
    expect(summary[:tiers_recorded]).to eq(4)
    expect(summary[:alerted]).to eq(2)
    expect(summary[:auto_lost]).to eq(0)

    expect(PallasTrade::DisputeDeadlineAlert.where(dispute_id: soon.id).pluck(:tier)).to eq(['t3'])
    expect(PallasTrade::DisputeDeadlineAlert.where(dispute_id: late.id).pluck(:tier)).to contain_exactly('t3', 't1', 'overdue')
  end

  # AC-007（既有事件语义不变：仍按桶逐条发布）
  it 'still publishes the legacy bucket events for every candidate' do
    soon = make_dispute(due_at: Time.current + 40.hours, reference: 'dp_d14bs_soon2')
    late = make_dispute(due_at: Time.current - 2.hours, reference: 'dp_d14bs_late2')
    published = []
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
    allow(PallasTrade::Events).to receive(:publish) { |name, payload| published << [name, payload] }

    described_class.perform_now

    expect(published).to include(['dispute.evidence_due_soon', hash_including('id' => soon.prefixed_id)])
    expect(published).to include(['dispute.evidence_overdue', hash_including('id' => late.prefixed_id)])
  end
end
