# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-6 AC-4P6-10
require 'rails_helper'

RSpec.describe PallasTrade::Reconciliations::SourceResult, type: :service do
  def build(**over)
    described_class.new(
      source_type: :payment, source_id: 'py_1', status: described_class::MATCHED,
      reasons: [], local_amount: 100.0, local_currency: 'USD',
      provider_gross_amount: 100.0, provider_currency: 'USD', provider_settlement_status: 'settled',
      provider_payment_reference: 'pi_1', observed_at: Time.utc(2026, 9, 6)
    ).then { |r| over.any? ? described_class.new(**r.to_h.merge(over)) : r }
  end

  it 'AC-4P6-10 exposes statuses and helper predicates, frozen' do
    expect(described_class::STATUSES).to eq(%w[PENDING MATCHED MISMATCH NEEDS_ATTENTION NOT_APPLICABLE UNSUPPORTED])
    m = build
    expect(m).to be_matched
    expect(m).not_to be_mismatch
    expect(build(status: 'MISMATCH', reasons: ['AMOUNT_MISMATCH'])).to be_mismatch
    expect(build(status: 'PENDING', reasons: ['SETTLEMENT_PENDING'])).to be_pending
    expect(build(status: 'NEEDS_ATTENTION', reasons: ['PROVIDER_UNAVAILABLE'])).to be_needs_attention
    expect(build(status: 'NOT_APPLICABLE')).to be_not_applicable
    expect(build(status: 'UNSUPPORTED', reasons: ['PROVIDER_CONTRACT_UNSUPPORTED'])).to be_unsupported
    expect(m).to be_frozen
  end

  it 'AC-4P6-10 rejects unknown keys and unknown statuses are allowed only via const list' do
    expect { described_class.new(source_type: :payment, status: 'NOPE', bogus: 1) }.to raise_error(ArgumentError)
  end

  it 'to_h / as_json parity' do
    r = build
    expect(r.as_json).to eq(r.to_h)
  end
end
