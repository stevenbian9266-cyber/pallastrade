# frozen_string_literal: true

require 'rails_helper'

# PRD-20260912-payments-dsp-p7-4-dispute-evidence-snapshot
# AC-P74-01..11 —— 争议证据快照：只读投影 + 每段 availability/reason + 禁推导 + 默认零 provider I/O + 不提交。
RSpec.describe PallasTrade::Disputes::BuildEvidenceSnapshot, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_price: 50, shipment_cost: 0).tap do |o|
      o.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)
    end
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: order.total, state: 'completed',
                     response_code: 'pi_p74_anchor', source: nil, skip_source_requirement: true)
  end
  let(:txn) { PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: order.total) }

  let(:dispute) do
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p74_#{SecureRandom.hex(4)}",
      state: 'needs_response', amount: 12.34, currency: 'usd',
      private_metadata: { 'provider_status' => 'needs_response' },
      funds_withdrawn_at: Time.current,
      commerce_transaction: txn, payment: payment, order: order
    )
  end

  before do
    shipment = order.shipments.first
    shipment.update_columns(tracking: 'TRK-P74-1', shipped_at: 2.days.ago, state: 'shipped')
    create(:refund, payment: payment, amount: 5, transaction_id: 're_p74')
    PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute)
  end

  # 重写契约的伪网关（capability = 真）：AR 子类需显式类名（匿名类会在 set_name 处报错）
  let(:fake_supported_gateway) do
    Class.new(PallasTrade::PaymentMethod) do
      def self.name = 'P7FourFakeGateway'

      def fetch_dispute_details(dispute:)
        { provider_dispute_reference: dispute.provider_dispute_reference, status: 'needs_response',
          amount: 12.34, currency: 'usd', reason: 'fraudulent', network_reason_code: nil,
          evidence_due_at: Time.current + 3.days, evidence_submitted_at: nil, has_evidence: false }
      end
    end.new
  end

  let(:fake_broken_gateway) do
    Class.new(PallasTrade::PaymentMethod) do
      def self.name = 'P7FourBrokenGateway'

      def fetch_dispute_details(*)
        raise PallasTrade::Core::GatewayError, 'provider down'
      end
    end.new
  end

  def payment_double_for(gateway)
    double('payment', id: payment.id, prefixed_id: payment.prefixed_id, response_code: payment.response_code,
                      amount: payment.amount, currency: payment.currency, state: payment.state,
                      payment_method: gateway)
  end

  def build(fetch: false)
    result = described_class.call(dispute: dispute, fetch: fetch)

    expect(result).to be_success
    result.value
  end

  it 'AC-P74-01 各段 available 且字段与源记录一致' do
    snapshot = build

    expect(snapshot.dispute_id).to eq(dispute.prefixed_id)
    expect(snapshot.section('order')['data']['number']).to eq(order.number)
    expect(snapshot.section('order')['data']['currency']).to eq(order.currency)
    expect(snapshot.section('transaction')['data']['id']).to eq(txn.prefixed_id)
    expect(snapshot.section('payment')['data']['id']).to eq(payment.prefixed_id)
    expect(snapshot.section('payment')['data']['provider_payment_reference']).to eq('pi_p74_anchor')
    expect(snapshot.section('refunds')['data']['items'].size).to eq(1)
    expect(snapshot.section('refunds')['data']['total'].to_d).to eq(5.to_d)
    expect(snapshot.section('journal')['data']['entries'].map { |e| e['entry_type'] }).to eq(
      ['DISPUTE_FUNDS_WITHDRAWN']
    )
    expect(snapshot.section('reconciliation')['data']['classification']).to eq('aligned')
  end

  it 'AC-P74-02 禁推导：delivered_at / proof_of_delivery 恒 not_available（不得由 shipped_at 推导）' do
    snapshot = build
    data = snapshot.section('fulfillment')['data']

    expect(data['shipments'].first['shipped_at']).to be_present # 有发货时间…
    expect(data['delivered_at']['availability']).to eq('not_available') # …但送达事实不可得
    expect(data['delivered_at']['reason']).to eq('not_recorded')
    expect(data['delivered_at']['value']).to be_nil
    expect(data['proof_of_delivery']['availability']).to eq('not_available')
  end

  it 'AC-P74-03 客户沟通恒 not_available（系统无结构化记录）' do
    section = build.section('customer_communication')

    expect(section['availability']).to eq('not_available')
    expect(section['reason']).to eq('not_recorded')
  end

  it 'AC-P74-04 默认零 provider I/O；无 capability → not_supported' do
    expect(payment_method).not_to receive(:fetch_dispute_details)

    snapshot = build(fetch: false)

    expect(snapshot.section('provider')['availability']).to eq('not_available')
    expect(snapshot.section('provider')['reason']).to eq('not_requested')
    expect(snapshot.missing_evidence).to include('PROVIDER_SNAPSHOT_UNSUPPORTED')
  end

  it 'AC-P74-04 有 capability + fetch: true → provider 段归一化可用' do
    allow(dispute).to receive(:payment).and_return(payment_double_for(fake_supported_gateway))

    snapshot = build(fetch: true)

    expect(snapshot.section('provider')['availability']).to eq('available')
    expect(snapshot.section('provider')['data'][:status]).to eq('needs_response')
    expect(snapshot.missing_evidence).not_to include('PROVIDER_SNAPSHOT_UNSUPPORTED')
  end

  it 'AC-P74-05 provider 故障 → provider_unavailable（不阻断其他段）' do
    allow(dispute).to receive(:payment).and_return(payment_double_for(fake_broken_gateway))

    snapshot = build(fetch: true)

    expect(snapshot.section('provider')['reason']).to eq('provider_unavailable')
    expect(snapshot.missing_evidence).to include('PROVIDER_SNAPSHOT_UNAVAILABLE')
    expect(snapshot.section('order')['availability']).to eq('available') # 其他段不受影响
  end

  it 'AC-P74-06 missing_evidence 分类：tracking / shipped_at / 送达证明 / 退款重叠' do
    snapshot = build

    expect(snapshot.missing_evidence).to include(
      'PROOF_OF_DELIVERY_NOT_AVAILABLE', 'CUSTOMER_COMMUNICATION_NOT_RECORDED', 'REFUND_OVERLAP_PRESENT'
    )
    expect(snapshot.missing_evidence).not_to include('TRACKING_MISSING', 'SHIPPED_AT_MISSING')

    order.shipments.first.update_columns(tracking: nil, shipped_at: nil)
    snapshot = build

    expect(snapshot.missing_evidence).to include('TRACKING_MISSING', 'SHIPPED_AT_MISSING')
  end

  it 'AC-P74-07 只读：构建前后相关表与 dispute 属性零变化' do
    counts = lambda do
      [PallasTrade::Dispute.count, PallasTrade::Payment.count, PallasTrade::Order.count,
       PallasTrade::Refund.count, PallasTrade::FinancialLedgerEntry.count]
    end
    before_counts = counts.call
    dispute_before = dispute.reload.attributes

    build

    expect(counts.call).to eq(before_counts)
    expect(dispute.reload.attributes).to eq(dispute_before)
  end

  it 'AC-P74-08 无 order / 无 payment 锚点 → 对应段 not_available 且构建成功' do
    orphan = PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p74_orphan_#{SecureRandom.hex(3)}",
      state: 'opened', amount: 9.99, currency: 'usd'
    )

    result = described_class.call(dispute: orphan)
    expect(result).to be_success
    snapshot = result.value

    expect(snapshot.section('order')['reason']).to eq('order_missing')
    expect(snapshot.section('payment')['reason']).to eq('payment_anchor_missing')
    expect(snapshot.missing_evidence).to include('ORDER_MISSING', 'PAYMENT_ANCHOR_MISSING')
  end

  it 'AC-P74-09 VO 不可变 + 白名单校验' do
    snapshot = build

    expect(snapshot).to be_frozen
    expect { PallasTrade::Disputes::EvidenceSnapshot.new(bogus: 1) }.to raise_error(
      ArgumentError, /Unknown EvidenceSnapshot attributes/
    )
  end

  it 'AC-P74-10 日志不含 PII（邮箱/地址不进日志）' do
    logged = []
    logger = instance_double(Logger)
    allow(logger).to receive(:info) { |message| logged << message }
    allow(logger).to receive(:warn) { |message| logged << message }
    allow(logger).to receive(:error) { |message| logged << message }
    allow(Rails).to receive(:logger).and_return(logger)

    snapshot = build

    expect(snapshot.section('order')['data']['email']).to be_present # VO 内有（业务需要）
    expect(logged.join).not_to include(order.email.to_s) if order.email.present?
  end

  it 'AC-P74-11 不提交：submission_ready 恒 false' do
    snapshot = build

    expect(snapshot.submission_ready).to be(false)
    expect(snapshot.submission_ready?).to be(false)
  end
end
