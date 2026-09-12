# frozen_string_literal: true

require 'rails_helper'

# PRD-20260912-payments-dsp-p7-6-dispute-recovery
# AC-P76-15/16 —— 收敛候选本地预筛：三类 selection / 优先级去重 / 排序截断 / 零 provider I/O。
RSpec.describe PallasTrade::Disputes::ScanRecoveryCandidates, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_price: 50, shipment_cost: 0).tap do |o|
      o.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)
    end
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: order.total, state: 'completed',
                     response_code: 'pi_p76_scan', source: nil, skip_source_requirement: true)
  end
  let(:txn) do
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: order.total)
  end

  def make_dispute(state: 'opened', funds_withdrawn_at: nil, attention_reason: nil, reference: nil,
                   provider_status: nil)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: reference || "dp_p76s_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd',
      private_metadata: provider_status ? { 'provider_status' => provider_status } : {},
      funds_withdrawn_at: funds_withdrawn_at,
      attention_reason: attention_reason,
      commerce_transaction: txn, payment: payment, order: order
    )
  end

  def make_stale(reference: nil)
    make_dispute(state: 'opened', reference: reference).tap do |dispute|
      dispute.update_columns(updated_at: Time.current - 48.hours)
    end
  end

  def scan(limit: 50, verify_after_hours: 24, now: Time.current)
    result = described_class.call(now: now, limit: limit, verify_after_hours: verify_after_hours)

    expect(result).to be_success
    result.value
  end

  it 'AC-P76-15 三类 selection 各自命中；刚更新的活跃争议不进 stale_active' do
    flagged = make_dispute(state: 'needs_response', attention_reason: 'unlinked_payment', reference: 'dp_p76s_att')
    gap = make_dispute(state: 'lost', funds_withdrawn_at: Time.current - 2.hours, reference: 'dp_p76s_gap')
    stale = make_stale(reference: 'dp_p76s_stale')
    fresh = make_dispute(state: 'opened', reference: 'dp_p76s_fresh')

    value = scan
    selections = value[:candidates].to_h { |item| [item[:dispute_id], item[:selection]] }

    expect(selections[flagged.prefixed_id]).to eq('attention')
    expect(selections[gap.prefixed_id]).to eq('journal_gap')
    expect(selections[stale.prefixed_id]).to eq('stale_active')
    expect(selections[fresh.prefixed_id]).to be_nil
    expect(value[:scanned_count]).to eq(3)
  end

  it 'AC-P76-15 排序为 attention → journal_gap → stale_active，且 limit 截断生效' do
    make_stale(reference: 'dp_p76s_z_stale')
    make_dispute(state: 'lost', funds_withdrawn_at: Time.current - 2.hours, reference: 'dp_p76s_z_gap')
    make_dispute(state: 'opened', attention_reason: 'unlinked_payment', reference: 'dp_p76s_z_att')

    value = scan(limit: 2)

    expect(value[:candidates].map { |item| item[:selection] }).to eq(%w[attention journal_gap])
    expect(value[:scanned_count]).to eq(2)
  end

  it 'AC-P76-15 一条争议命中多类 → 只保留最高优先级（attention）' do
    dispute = make_dispute(state: 'opened', funds_withdrawn_at: Time.current - 2.hours,
                           attention_reason: 'unlinked_payment', reference: 'dp_p76s_multi')
    dispute.update_columns(updated_at: Time.current - 48.hours)

    value = scan

    expect(value[:candidates].map { |item| item[:selection] }).to eq(['attention'])
    expect(value[:candidates].first[:dispute_id]).to eq(dispute.prefixed_id)
    expect(value[:candidates].first[:age_hours]).to be_within(1.0).of(48.0)
  end

  it 'AC-P76-15 候选项携带 AR 记录与 prefixed id（供执行期复用）' do
    dispute = make_dispute(state: 'opened', attention_reason: 'unlinked_payment', reference: 'dp_p76s_carry')

    item = scan[:candidates].find { |candidate| candidate[:dispute_id] == dispute.prefixed_id }

    expect(item[:dispute]).to be_a(PallasTrade::Dispute)
    expect(item[:dispute].id).to eq(dispute.id)
    expect(item[:state]).to eq('opened')
    expect(item[:attention_reason]).to eq('unlinked_payment')
  end

  it 'AC-P76-16 零 provider I/O：扫描期间任何 provider 只读调用都会炸' do
    make_stale(reference: 'dp_p76s_noio')
    make_dispute(state: 'lost', funds_withdrawn_at: Time.current - 2.hours, reference: 'dp_p76s_noio_gap')
    allow_any_instance_of(payment_method.class).to receive(:fetch_dispute_details).
      and_raise(StandardError, 'scan must not touch provider')

    value = scan

    expect(value[:candidates]).not_to be_empty
  end

  it 'AC-P76-16 终态且账行齐备的争议不在任何 selection' do
    # `provider_status` 元数据由入口（P7-1）写入 —— 缺它时本地事实会降为 AMBIGUOUS（属“不猜”降级，另测）
    dispute = make_dispute(state: 'lost', funds_withdrawn_at: Time.current - 2.hours,
                           provider_status: 'lost', reference: 'dp_p76s_done')
    PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute, fact_type: 'DISPUTE_FUNDS_WITHDRAWN')
    dispute.update_columns(updated_at: Time.current - 72.hours)

    expect(scan[:candidates].map { |item| item[:dispute_id] }).not_to include(dispute.prefixed_id)
  end
end
