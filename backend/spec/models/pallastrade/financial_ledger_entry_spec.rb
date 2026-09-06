# frozen_string_literal: true

# PRD-20260905-payments-fin-p4-2 AC-4P2-01/02/03/09/10/11
require 'rails_helper'

RSpec.describe PallasTrade::FinancialLedgerEntry, type: :model do
  let(:store) { @default_store }

  def make_transaction(amount: 100)
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: amount)
  end

  def make_entry(txn: nil, entry_type: 'CASH_CAPTURED', amount: 100.0, currency: 'USD', **overrides)
    described_class.create!(
      { commerce_transaction: txn || make_transaction,
        entry_type: entry_type, amount: amount, currency: currency,
        idempotency_key: "key_#{SecureRandom.hex(8)}",
        effective_at: Time.current }.merge(overrides)
    )
  end

  it 'AC-4P2-01 creates an entry with required fields' do
    entry = make_entry
    expect(entry).to be_persisted
    expect(entry.commerce_transaction_id).to be_present
    expect(entry.currency).to eq('USD')
    expect(entry.amount).to eq(100.0)
    expect(entry.entry_type).to eq('CASH_CAPTURED')
    expect(entry.state).to eq('posted')
    expect(entry.idempotency_key).to be_present
    expect(entry.effective_at).to be_present
    expect(entry.recorded_at).to be_present
    expect(entry.prefixed_id).to start_with('fle')
  end

  it 'AC-4P2-01 validates presence of commerce_transaction/currency/amount/entry_type/effective_at/idempotency_key' do
    expect { described_class.create!(commerce_transaction: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { make_entry(currency: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { make_entry(amount: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { make_entry(entry_type: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { make_entry(idempotency_key: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { make_entry(effective_at: nil) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'AC-4P2-02/AC-4P4-03 accepts activated entry types, rejects reserved/unactivated' do
    %w[CASH_CAPTURED STORE_CREDIT_APPLIED OFFLINE_PAYMENT_RECORDED REFUND_SUCCEEDED ORDER_ALLOCATION].each do |type|
      expect(make_entry(entry_type: type)).to be_persisted
    end
    %w[PSP_FEE PSP_NET_SETTLEMENT].each do |type|
      expect { make_entry(entry_type: type) }.to raise_error(ActiveRecord::RecordInvalid), "expected #{type} rejected"
    end
  end

  it 'AC-4P2-03 immutable: update of financial fields is rejected (ImmutableError), DB unchanged' do
    entry = make_entry
    original = entry.amount

    expect { entry.update!(amount: 50) }.to raise_error(PallasTrade::FinancialLedgerEntry::ImmutableError)
    expect { entry.update!(entry_type: 'REFUND_SUCCEEDED') }.to raise_error(PallasTrade::FinancialLedgerEntry::ImmutableError)
    expect { entry.update!(commerce_transaction: make_transaction) }.to raise_error(PallasTrade::FinancialLedgerEntry::ImmutableError)
    expect { entry.update!(currency: 'EUR') }.to raise_error(PallasTrade::FinancialLedgerEntry::ImmutableError)
    expect(entry.reload.amount).to eq(original)
  end

  it 'AC-4P2-03 immutable: direct update_columns of non-state columns is rejected' do
    entry = make_entry
    expect { entry.update_columns(amount: 1) }.to raise_error(PallasTrade::FinancialLedgerEntry::ImmutableError)
    expect { entry.update_columns(provider_reference: 'x') }.to raise_error(PallasTrade::FinancialLedgerEntry::ImmutableError)
    expect(entry.reload.amount).to eq(100.0)
  end

  it 'AC-4P2-03 immutable: reversal state transition is the only allowed in-place mutation' do
    entry = make_entry
    entry.mark_reversed!
    expect(entry.reload).to be_reversed
    expect(entry.reversed_at).to be_present
    expect(entry.amount).to eq(100.0) # 金额从未被改
  end

  it 'AC-4P2-09 fact_posting_key is stable for the same fact and distinct across sources' do
    txn = make_transaction
    fact_a = PallasTrade::FinancialFact.new(
      fact_type: 'CASH_CAPTURED', status: 'CONFIRMED', amount: 100, currency: 'USD',
      instrument_class: 'PSP_CASH', commerce_transaction_id: txn.prefixed_id,
      payment_id: 'py_a', effective_at: Time.utc(2026, 9, 6, 0, 0, 0)
    )
    fact_a2 = PallasTrade::FinancialFact.new(
      fact_type: 'CASH_CAPTURED', status: 'CONFIRMED', amount: 100, currency: 'USD',
      instrument_class: 'PSP_CASH', commerce_transaction_id: txn.prefixed_id,
      payment_id: 'py_a', effective_at: Time.utc(2026, 9, 6, 0, 0, 0)
    )
    fact_b = PallasTrade::FinancialFact.new(
      fact_type: 'CASH_CAPTURED', status: 'CONFIRMED', amount: 60, currency: 'USD',
      instrument_class: 'PSP_CASH', commerce_transaction_id: txn.prefixed_id,
      payment_id: 'py_b', effective_at: Time.utc(2026, 9, 6, 0, 0, 0)
    )

    expect(described_class.fact_posting_key(fact_a)).to eq(described_class.fact_posting_key(fact_a2))
    expect(described_class.fact_posting_key(fact_a)).not_to eq(described_class.fact_posting_key(fact_b))
  end

  it 'AC-4P2-10 naming discipline: no ambiguous transaction_id attribute on ledger entries' do
    entry = make_entry
    expect(entry).not_to respond_to(:transaction_id)
    expect(entry.respond_to?(:commerce_transaction_id)).to be(true)
  end

  it 'AC-4P2-11 by_transaction / active scopes behave (reversal filtered out after reverse)' do
    txn = make_transaction
    entry = make_entry(txn: txn)
    expect(described_class.by_transaction(txn)).to include(entry)
    expect(described_class.active).to include(entry)

    entry.mark_reversed!
    expect(described_class.active).not_to include(entry)
  end

  it 'AC-4P2-03/09 idempotency_key uniqueness is enforced (validation + DB unique backup)' do
    txn = make_transaction
    make_entry(txn: txn, idempotency_key: 'dup_key')
    # uniqueness validation 先拦截常规重复；DB UNIQUE 兜底并发竞态（Post 服务 rescue RecordNotUnique）
    expect { make_entry(txn: txn, idempotency_key: 'dup_key') }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
