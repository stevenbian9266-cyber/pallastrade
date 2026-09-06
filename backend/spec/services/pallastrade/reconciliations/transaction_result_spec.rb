# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-7 AC-4P7-09
require 'rails_helper'

RSpec.describe PallasTrade::Reconciliations::TransactionResult, type: :service do
  def build(**over)
    summary = PallasTrade::Reconciliations::TransactionFinancialSummary.new(
      commercial_amount: 100.0, cash_captured: 100.0, store_credit_applied: 0.0,
      offline_payment_recorded: 0.0, refund_total: 0.0, allocation_total: 100.0,
      currency: 'USD', provider_fee: 2.9, provider_net: 97.1
    )
    described_class.new(
      transaction_id: 'txn_1', status: described_class::MATCHED, reasons: [],
      summary: summary, source_reconciliations: [],
      provider_gross_amount: 100.0, provider_currency: 'USD', provider_fee: 2.9, provider_net: 97.1,
      observed_at: Time.utc(2026, 9, 6)
    ).then { |r| over.any? ? described_class.new(**r.to_h.merge(over)) : r }
  end

  it 'AC-4P7-09 exposes six-state constants + helper predicates, frozen' do
    expect(described_class::STATUSES).to eq(%w[PENDING MATCHED MISMATCH NEEDS_ATTENTION NOT_APPLICABLE UNSUPPORTED])
    m = build
    expect(m).to be_matched
    expect(m).not_to be_mismatch
    expect(build(status: 'MISMATCH', reasons: ['ALLOCATION_MISMATCH'])).to be_mismatch
    expect(build(status: 'PENDING', reasons: ['SETTLEMENT_PENDING'])).to be_pending
    expect(build(status: 'NEEDS_ATTENTION', reasons: ['JOURNAL_POSTING_MISSING'])).to be_needs_attention
    expect(build(status: 'NOT_APPLICABLE')).to be_not_applicable
    expect(build(status: 'UNSUPPORTED', reasons: ['PROVIDER_CONTRACT_UNSUPPORTED'])).to be_unsupported
    expect(m).to be_frozen
    expect(m.transaction_id).to eq('txn_1')
    expect(m.summary.cash_captured).to eq(100.0)
    expect(m.provider_gross_amount).to eq(100.0)
    expect(m.reasons).to eq([])
  end

  it 'rejects unknown keys' do
    expect { described_class.new(transaction_id: 'txn_1', status: 'NOPE', bogus: 1) }.to raise_error(ArgumentError)
  end

  it 'to_h / as_json parity' do
    r = build
    expect(r.as_json).to eq(r.to_h)
  end
end
