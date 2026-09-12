# frozen_string_literal: true

require 'rails_helper'

# PRD-20260912-payments-dsp-p7-5-dispute-deadline-sweep
# AC-P75-01..05、AC-P75-10 —— 期限扫描：分桶/边界/终态排除/窗口/缺口清单/只读。
RSpec.describe PallasTrade::Disputes::ScanDeadlines, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_price: 50, shipment_cost: 0).tap do |o|
      o.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)
    end
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: order.total, state: 'completed',
                     response_code: 'pi_p75_anchor', source: nil, skip_source_requirement: true)
  end
  let(:txn) { PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: order.total) }

  def make_dispute(state: 'needs_response', due_at: nil, reference: nil)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: reference || "dp_p75_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd',
      private_metadata: { 'provider_status' => 'needs_response' },
      evidence_due_at: due_at,
      commerce_transaction: txn, payment: payment, order: order
    )
  end

  def scan(window_hours: 72, now: Time.current)
    result = described_class.call(window_hours: window_hours, now: now)

    expect(result).to be_success
    result.value
  end

  it 'AC-P75-01 分桶：临近进 due_soon、逾期进 overdue（含 hours_remaining）' do
    now = Time.current.change(usec: 0)
    soon = make_dispute(due_at: now + 48.hours)
    late = make_dispute(due_at: now - 5.hours)

    value = scan(now: now)

    expect(value[:due_soon].map { |i| i[:dispute_id] }).to eq([soon.prefixed_id])
    expect(value[:overdue].map { |i| i[:dispute_id] }).to eq([late.prefixed_id])
    expect(value[:due_soon].first[:hours_remaining]).to be_within(0.05).of(48.0)
    expect(value[:overdue].first[:hours_remaining]).to be_within(0.05).of(-5.0)
  end

  it 'AC-P75-02 边界：due_at == now → due_soon（不算逾期）' do
    now = Time.current.change(usec: 0)
    edge = make_dispute(due_at: now)

    value = scan(now: now)

    expect(value[:due_soon].map { |i| i[:dispute_id] }).to include(edge.prefixed_id)
    expect(value[:overdue]).to be_empty
    expect(value[:due_soon].first[:hours_remaining]).to eq(0.0)
  end

  it 'AC-P75-03 窗口生效：window_hours=24 排除 48h 后的争议' do
    now = Time.current.change(usec: 0)
    far = make_dispute(due_at: now + 48.hours)

    expect(scan(window_hours: 24, now: now)[:due_soon]).to be_empty
    expect(scan(window_hours: 72, now: now)[:due_soon].map { |i| i[:dispute_id] }).to eq([far.prefixed_id])
  end

  it 'AC-P75-04 终态与无截止日的争议都不进桶' do
    now = Time.current.change(usec: 0)
    %w[won lost accepted expired closed].each do |state|
      make_dispute(state: state, due_at: now + 10.hours)
    end
    make_dispute(due_at: nil)

    value = scan(now: now)

    expect(value[:due_soon]).to be_empty
    expect(value[:overdue]).to be_empty
    expect(value[:scanned_count]).to eq(0)
  end

  it 'AC-P75-05 候选项携带 missing_evidence（P7-4 缺口清单）' do
    now = Time.current.change(usec: 0)
    make_dispute(due_at: now + 6.hours)

    item = scan(now: now)[:due_soon].first

    expect(item[:missing_evidence]).to include('PROOF_OF_DELIVERY_NOT_AVAILABLE',
                                               'CUSTOMER_COMMUNICATION_NOT_RECORDED')
    expect(item[:evidence_unavailable]).to be(false)
    expect(item[:payment_id]).to eq(payment.prefixed_id)
    expect(item[:order_id]).to eq(order.prefixed_id)
  end

  it 'AC-P75-05 证据构建异常 → evidence_unavailable=true 且不阻断扫描' do
    now = Time.current.change(usec: 0)
    dispute = make_dispute(due_at: now + 5.hours)
    # 扫描从 DB 重新载入 dispute → 必须对**任意实例**打桩（关联层报错，避开 ServiceModule 类方法不可打桩的问题）
    allow_any_instance_of(PallasTrade::Dispute).to receive(:commerce_transaction).and_raise(StandardError, 'boom')

    value = scan(now: now)

    expect(value[:due_soon].map { |i| i[:dispute_id] }).to eq([dispute.prefixed_id])
    expect(value[:due_soon].first[:evidence_unavailable]).to be(true)
    expect(value[:due_soon].first[:missing_evidence]).to eq([])
  end

  it 'AC-P75-10 只读：扫描前后 disputes 行数与属性零变化' do
    now = Time.current.change(usec: 0)
    dispute = make_dispute(due_at: now + 3.hours)
    counts_before = [PallasTrade::Dispute.count, PallasTrade::Payment.count, PallasTrade::Order.count,
                     PallasTrade::FinancialLedgerEntry.count]
    attributes_before = dispute.reload.attributes

    scan(now: now)

    expect([PallasTrade::Dispute.count, PallasTrade::Payment.count, PallasTrade::Order.count,
            PallasTrade::FinancialLedgerEntry.count]).to eq(counts_before)
    expect(dispute.reload.attributes).to eq(attributes_before)
  end
end
