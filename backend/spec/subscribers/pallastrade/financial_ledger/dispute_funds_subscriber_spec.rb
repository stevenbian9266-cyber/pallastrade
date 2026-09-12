# frozen_string_literal: true

require 'rails_helper'

# PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile AC-P73-09
# `FinancialLedger::DisputeFundsSubscriber` —— 争议资金事件 → PostDispute 接线（async、幂等、异常不外抛）。
RSpec.describe PallasTrade::FinancialLedger::DisputeFundsSubscriber, type: :subscriber do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end
  let(:txn) { PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100) }

  def make_dispute(funds_withdrawn_at: nil, state: 'needs_response')
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd',
      private_metadata: { 'provider_status' => state },
      funds_withdrawn_at: funds_withdrawn_at,
      commerce_transaction: txn, payment: payment
    )
  end

  def event_for(dispute, name)
    double('event', name: name, payload: { 'id' => dispute.prefixed_id })
  end

  it 'AC-P73-09 订阅两个资金事件' do
    expect(described_class.subscription_patterns).to contain_exactly(
      'dispute.funds_withdrawn', 'dispute.funds_reinstated'
    )
  end

  it 'AC-P73-09 funds_withdrawn 事件 → 产生账行' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)

    described_class.new.handle(event_for(dispute, 'dispute.funds_withdrawn'))

    expect(PallasTrade::FinancialLedgerEntry.where(dispute_id: dispute.id).pluck(:entry_type)).to eq(
      ['DISPUTE_FUNDS_WITHDRAWN']
    )
  end

  it 'AC-P73-09 未知 dispute → 安全跳过（不抛错、零账行）' do
    described_class.new.handle(double('event', name: 'dispute.funds_withdrawn', payload: { 'id' => 'dsp_missing' }))

    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-P73-09 不可入账事实（缺资金时间戳）→ 记日志不抛错（skip reason 可见）' do
    dispute = make_dispute # opened：无 funds 时间戳 → 幂等键无法派生，不猜
    logged = []
    logger = instance_double(Logger)
    allow(logger).to receive(:info) { |message| logged << message }
    allow(logger).to receive(:error)
    allow(Rails).to receive(:logger).and_return(logger)

    described_class.new.handle(event_for(dispute, 'dispute.funds_withdrawn'))

    expect(logged.first).to include('skip ledger posting', 'effective_at_missing')
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-P73-09 posting 异常 → rescue 记录，不阻断争议落库' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)
    logger = instance_double(Logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(Rails).to receive(:logger).and_return(logger)
    allow(PallasTrade::Dispute).to receive(:find_by_param).and_raise(StandardError, 'ledger down')

    expect { described_class.new.handle(event_for(dispute, 'dispute.funds_withdrawn')) }.not_to raise_error
    expect(logger).to have_received(:error)
  end
end
