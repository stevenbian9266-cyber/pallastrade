# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-7 AC-4P7-09
require 'rails_helper'

RSpec.describe PallasTrade::Reconciliations::TransactionFinancialSummary, type: :service do
  def core(s)
    s.to_h.slice(*described_class::CORE_ATTRIBUTES)
  end

  def build(**over)
    s = described_class.new(
      commercial_amount: 100.0, cash_captured: 100.0, store_credit_applied: 0.0,
      offline_payment_recorded: 0.0, refund_total: 0.0, allocation_total: 100.0,
      currency: 'USD', provider_fee: 2.9, provider_net: 97.1
    )
    over.any? ? described_class.new(**core(s).merge(over)) : s
  end

  it 'AC-4P7-09 exposes §25 fields + derived helpers, frozen' do
    s = build
    expect(s.commercial_amount).to eq(100.0)
    expect(s.cash_captured).to eq(100.0)
    expect(s.gross_value_received).to eq(100.0)
    expect(s.net_customer_value).to eq(100.0)
    expect(s.unallocated_amount).to eq(0.0)
    expect(s.currency).to eq('USD')
    expect(s.provider_fee).to eq(2.9)
    expect(s.provider_net).to eq(97.1)
    expect(s).to be_frozen
  end

  it 'AC-4P7-09 gross = cash + store_credit + offline; net = gross − refund' do
    s = build(cash_captured: 80.0, store_credit_applied: 10.0, offline_payment_recorded: 10.0, refund_total: 20.0)
    expect(s.gross_value_received).to eq(100.0)
    expect(s.net_customer_value).to eq(80.0)
  end

  it 'AC-4P7-09 short_paid?/overpaid? reflect commercial comparison (AC-4016)' do
    expect(build(cash_captured: 90.0)).to be_short_paid
    expect(build(cash_captured: 90.0)).not_to be_overpaid
    expect(build(cash_captured: 110.0)).to be_overpaid
    expect(build(cash_captured: 100.0)).not_to be_short_paid
    expect(build(cash_captured: 100.0)).not_to be_overpaid
  end

  it 'AC-4P7-09 unallocated = cash − allocation (combination split view)' do
    s = build(cash_captured: 100.0, allocation_total: 60.0)
    expect(s.unallocated_amount).to eq(40.0)
  end

  it 'to_h / as_json parity' do
    s = build
    expect(s.as_json).to eq(s.to_h)
  end
end
