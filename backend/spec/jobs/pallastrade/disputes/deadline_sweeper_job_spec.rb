# frozen_string_literal: true

require 'rails_helper'
# 调度常量定义在 config/sidekiq_schedule.rb（仅 Sidekiq server 进程 require）→ 用例显式加载
require Rails.root.join('config/sidekiq_schedule')

ActiveJob::Base.queue_adapter = :test

# PRD-20260912-payments-dsp-p7-5-dispute-deadline-sweep
# AC-P75-06..09 —— sweeper job：事件+日志、零业务动作、单条隔离、调度登记。
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
                     response_code: 'pi_p75_sweep', source: nil, skip_source_requirement: true)
  end
  let(:txn) { PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: order.total) }

  let(:logged) { [] }
  let(:logger) do
    instance_double(Logger).tap do |double|
      allow(double).to receive(:info) { |message| logged << message }
      allow(double).to receive(:error) { |message| logged << message }
    end
  end

  def make_dispute(state: 'needs_response', due_at: nil, reference: nil)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: reference || "dp_p75s_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd',
      private_metadata: { 'provider_status' => 'needs_response' },
      evidence_due_at: due_at,
      commerce_transaction: txn, payment: payment, order: order
    )
  end

  before do
    allow(Rails).to receive(:logger).and_return(logger)
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
  end

  it 'AC-P75-06 逐条发布事件（按桶命名）+ 结构化日志 + 摘要' do
    soon = make_dispute(due_at: Time.current + 30.hours)
    late = make_dispute(due_at: Time.current - 2.hours)

    expect(PallasTrade::Events).to receive(:publish).with(
      'dispute.evidence_due_soon', hash_including('id' => soon.prefixed_id)
    ).and_call_original
    expect(PallasTrade::Events).to receive(:publish).with(
      'dispute.evidence_overdue', hash_including('id' => late.prefixed_id)
    ).and_call_original

    summary = described_class.perform_now

    expect(summary[:published]).to eq(2)
    expect(summary[:failed]).to eq(0)
    expect(summary[:due_soon]).to eq(1)
    expect(summary[:overdue]).to eq(1)
    expect(logged.join).to include('disputes.deadline_sweeper')
    expect(logged.join).to include(soon.prefixed_id)
  end

  it 'AC-P75-06 payload 携带 hours_remaining 与 missing_evidence（让提醒可行动）' do
    dispute = make_dispute(due_at: Time.current + 12.hours)
    captured = nil
    allow(PallasTrade::Events).to receive(:publish) { |_name, payload| captured = payload }

    described_class.perform_now

    expect(captured['id']).to eq(dispute.prefixed_id)
    expect(captured['hours_remaining']).to be_a(Numeric)
    expect(captured['missing_evidence']).to include('PROOF_OF_DELIVERY_NOT_AVAILABLE')
  end

  it 'AC-P75-07 零业务动作：不改状态/不写库/不调用 provider' do
    dispute = make_dispute(due_at: Time.current + 8.hours)
    pm = payment.payment_method
    expect(pm).not_to receive(:fetch_dispute_details)
    expect(pm).not_to receive(:submit_dispute_evidence) if pm.respond_to?(:submit_dispute_evidence)
    counts_before = [PallasTrade::Dispute.count, PallasTrade::Payment.count, PallasTrade::Order.count,
                     PallasTrade::FinancialLedgerEntry.count]
    state_before = dispute.reload.state
    attributes_before = dispute.attributes

    described_class.perform_now

    expect(dispute.reload.state).to eq(state_before)
    expect(dispute.attributes).to eq(attributes_before)
    expect([PallasTrade::Dispute.count, PallasTrade::Payment.count, PallasTrade::Order.count,
            PallasTrade::FinancialLedgerEntry.count]).to eq(counts_before)
  end

  it 'AC-P75-08 单条异常隔离：一条失败不影响其余，job 不 raise' do
    bad = make_dispute(due_at: Time.current + 4.hours, reference: 'dp_p75s_bad')
    good = make_dispute(due_at: Time.current + 6.hours, reference: 'dp_p75s_good')
    allow(PallasTrade::Events).to receive(:publish) do |_name, payload|
      raise StandardError, 'event bus down' if payload['id'] == bad.prefixed_id
    end

    summary = nil
    expect { summary = described_class.perform_now }.not_to raise_error

    expect(summary[:failed]).to eq(1)
    expect(summary[:published]).to eq(1)
    expect(logged.join).to include('alert failed')
    expect(good.prefixed_id).to be_present
  end

  it 'AC-P75-09 调度登记存在（PALLAS_CART_SCHEDULE）' do
    entry = PALLAS_CART_SCHEDULE.find { |e| e[:name] == 'dispute_deadline_sweep' }

    expect(entry).to be_present
    expect(entry[:class]).to eq('PallasTrade::Disputes::DeadlineSweeperJob')
    expect(entry[:cron]).to eq('0 1 * * *')
    expect(entry[:args]).to eq([{ 'window_hours' => 72 }])
  end
end
