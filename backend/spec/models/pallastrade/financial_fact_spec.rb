# frozen_string_literal: true

# PRD-20260905-payments-fin-p4-1 AC-4P1-01
require 'rails_helper'

RSpec.describe PallasTrade::FinancialFact, type: :model do
  let(:attrs) do
    {
      fact_type: PallasTrade::FinancialFact::CASH_CAPTURED,
      status: PallasTrade::FinancialFact::CONFIRMED,
      amount: 40.0,
      currency: 'USD',
      instrument_class: PallasTrade::FinancialFact::PSP_CASH,
      commerce_transaction_id: 'txn_test',
      payment_id: 'py_test',
      provider: 'PallasTrade::Gateway::Bogus',
      provider_payment_reference: 'pi_test',
      evidence: [:payment_completed],
      reason_code: nil
    }
  end

  it 'AC-4P1-01 exposes the full FinancialFact contract attributes' do
    fact = described_class.new(**attrs)
    expect(fact.fact_type).to eq('CASH_CAPTURED')
    expect(fact.status).to eq('CONFIRMED')
    expect(fact.amount).to eq(40.0)
    expect(fact.currency).to eq('USD')
    expect(fact.instrument_class).to eq('PSP_CASH')
    expect(fact.commerce_transaction_id).to eq('txn_test')
    expect(fact.payment_id).to eq('py_test')
    expect(fact.provider_payment_reference).to eq('pi_test')
    expect(fact.evidence).to eq([:payment_completed])
  end

  it 'AC-4P1-01 rejects unknown attributes' do
    expect { described_class.new(**attrs.merge(bogus: 1)) }.to raise_error(ArgumentError, /Unknown FinancialFact attributes/)
  end

  it 'AC-4P1-01 is immutable after construction' do
    fact = described_class.new(**attrs)
    expect(fact).to be_frozen
    expect { fact.instance_variable_set(:@amount, 999) }.to raise_error(FrozenError)
  end

  it 'AC-4P1-01 exposes status/fact_type/instrument_class constants' do
    expect(described_class::STATUSES).to eq(%w[CONFIRMED AUTHORIZED_ONLY UNPAID AMBIGUOUS NOT_APPLICABLE UNSUPPORTED])
    # DSP-P7-3：争议域 5 个事实类型与 Disputes::DisputeFact::FACT_TYPES 同名单对齐（仅 2 类现金事实入账）
    expect(described_class::FACT_TYPES).to eq(
      %w[CASH_CAPTURED STORE_CREDIT_APPLIED OFFLINE_PAYMENT_RECORDED REFUND_SUCCEEDED ORDER_ALLOCATION
         DISPUTE_OPENED DISPUTE_FUNDS_WITHDRAWN DISPUTE_FUNDS_REINSTATED DISPUTE_WON DISPUTE_LOST NONE]
    )
    expect(described_class::INSTRUMENT_CLASSES).to eq(%w[PSP_CASH STORE_CREDIT OFFLINE UNKNOWN])
    # FIN-P4-4：ORDER_ALLOCATION 已激活（资金归属投影，非 cash）；PSP_FEE/NET 仍为 reserved（P4-5）
    expect(described_class::FACT_TYPES).to include('ORDER_ALLOCATION')
    # DSP-P7-3：非现金争议事实永不进入 Journal（防双记）
    expect(PallasTrade::FinancialLedgerEntry::ENTRY_TYPES).not_to include('DISPUTE_WON', 'DISPUTE_LOST', 'DISPUTE_OPENED')
  end

  it 'AC-4P1-01 predicate helpers behave' do
    fact = described_class.new(**attrs)
    expect(fact).to be_confirmed
    expect(fact).to be_cash_captured
    expect(fact).to be_postable_cash_fact
    expect(fact.to_h).to include(fact_type: 'CASH_CAPTURED', status: 'CONFIRMED', amount: 40.0)
    expect(fact.as_json).to include(status: 'CONFIRMED')
  end

  it 'AC-4P1-01 ambiguous/unsupported predicates' do
    amb = described_class.new(**attrs.merge(status: PallasTrade::FinancialFact::AMBIGUOUS))
    expect(amb).to be_ambiguous
    expect(amb).not_to be_confirmed
    uns = described_class.new(**attrs.merge(status: PallasTrade::FinancialFact::UNSUPPORTED, fact_type: PallasTrade::FinancialFact::NONE))
    expect(uns).to be_unsupported
    expect(uns).not_to be_postable_cash_fact
  end
end
