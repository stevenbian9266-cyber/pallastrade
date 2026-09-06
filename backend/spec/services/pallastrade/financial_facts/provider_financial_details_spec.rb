# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-5 AC-4P5-07
require 'rails_helper'

RSpec.describe PallasTrade::FinancialFacts::ProviderFinancialDetails, type: :service do
  let(:valid_attrs) do
    {
      provider: 'stripe',
      provider_payment_reference: 'pi_1',
      provider_charge_reference: 'ch_1',
      provider_balance_transaction_reference: 'txn_1',
      provider_refund_references: %w[re_1],
      gross_amount: 100.0,
      gross_currency: 'USD',
      refund_total: 20.0,
      refund_currency: 'USD',
      fee_amount: 3.0,
      fee_currency: 'USD',
      net_amount: 97.0,
      net_currency: 'USD',
      settlement_status: 'settled',
      observed_at: Time.utc(2026, 9, 6),
      raw_reference: 'pi_1'
    }
  end

  it 'AC-4P5-07 builds from whitelist attrs and freezes' do
    d = described_class.new(**valid_attrs)
    expect(d).to be_frozen
    expect(d.gross_amount).to eq(100.0)
    expect(d.fee_amount).to eq(3.0)
    expect(d.net_amount).to eq(97.0)
    expect(d.provider_charge_reference).to eq('ch_1')
    expect(d.provider_refund_references).to eq(%w[re_1])
    expect(d).to be_settled
    expect { d.instance_variable_set(:@gross_amount, 999) }.to raise_error(FrozenError)
  end

  it 'AC-4P5-07 from_hash normalizes string keys through the whitelist' do
    d = described_class.from_hash(valid_attrs.stringify_keys)
    expect(d).not_to be_nil
    expect(d.provider).to eq('stripe')
    expect(d.settlement_status).to eq('settled')
  end

  it 'AC-4P5-07 from_hash silently drops unknown keys (no partial-poisoning)' do
    d = described_class.from_hash(valid_attrs.merge(unknown: 'x', fee: 'y'))
    expect(d).not_to be_nil
    expect(d.to_h).not_to have_key(:unknown)
    expect(d.to_h).not_to have_key(:fee)
  end

  it 'AC-4P5-07 rejects unknown constructor keys' do
    expect { described_class.new(**valid_attrs.merge(bogus: 1)) }.to raise_error(ArgumentError)
  end

  it 'AC-4P5-04/07 nullable fee/net/refund supported (not settled → no guess)' do
    d = described_class.new(
      provider: 'stripe', provider_payment_reference: 'pi_1', gross_amount: 100.0,
      gross_currency: 'USD', settlement_status: 'requires_capture', observed_at: Time.current
    )
    expect(d).not_to be_settled
    expect(d.fee_amount).to be_nil
    expect(d.net_amount).to be_nil
    expect(d.refund_total).to be_nil
    expect(d.provider_charge_reference).to be_nil
  end

  it 'from_hash(nil) returns nil' do
    expect(described_class.from_hash(nil)).to be_nil
  end

  it 'exposes to_h / as_json parity' do
    d = described_class.new(**valid_attrs)
    expect(d.as_json).to eq(d.to_h)
  end
end
