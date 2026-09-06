# frozen_string_literal: true

# PRD-20260905-payments-fin-p4-2 AC-4P2-04/05
require 'rails_helper'

RSpec.describe PallasTrade::FinancialLedger::Reverse, type: :service do
  let(:store) { @default_store }

  def make_transaction
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100)
  end

  def make_entry(amount: 100.0, entry_type: 'CASH_CAPTURED')
    PallasTrade::FinancialLedgerEntry.create!(
      commerce_transaction: make_transaction,
      entry_type: entry_type, amount: amount, currency: 'USD',
      idempotency_key: "key_#{SecureRandom.hex(8)}",
      effective_at: Time.current
    )
  end

  it 'AC-4P2-04 reversal appends an opposite-sign entry and marks the original reversed (append-only)' do
    entry = make_entry
    result = described_class.call(entry: entry)
    expect(result).to be_success

    reversal = result.value
    expect(reversal).not_to eq(entry)
    expect(reversal.reversal_of).to eq(entry)
    expect(reversal.entry_type).to eq(entry.entry_type)
    expect(reversal.amount).to eq(-100.0)
    expect(reversal.state).to eq('posted')
    expect(reversal.idempotency_key).to eq("reversal:#{entry.idempotency_key}")

    expect(entry.reload).to be_reversed
    expect(entry.reversed_at).to be_present
    expect(entry.amount).to eq(100.0) # 原 entry 从未被改（FIN-INV-07）
    expect(PallasTrade::FinancialLedgerEntry.active).not_to include(entry)
  end

  it 'AC-4P2-05 an already-reversed entry cannot be reversed again' do
    entry = make_entry
    described_class.call(entry: entry)

    second = described_class.call(entry: entry.reload)
    expect(second).to be_failure
    expect(second.error.to_s).to match(/already reversed|active reversal/i)
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(2)
  end

  it 'AC-4P2-05 an entry with an existing active reversal cannot gain another' do
    entry = make_entry
    reversal = described_class.call(entry: entry).value

    # 直接尝试对原 entry 再 reverse（虽已 reversed，模拟并发/绕过路径）
    duplicate = described_class.call(entry: entry.reload)
    expect(duplicate).to be_failure

    # reversal entry 本身仍可再 reverse（恢复语义）——append-only 支持链式修正
    restore = described_class.call(entry: reversal)
    expect(restore).to be_success
    expect(restore.value.amount).to eq(100.0)
    expect(reversal.reload).to be_reversed
  end

  it 'AC-4P2-04/05 idempotent reversal key is unique and DB partial-unique guards one active reversal' do
    entry = make_entry
    described_class.call(entry: entry)
    # 二次 attempt 不会创建额外 reversal（幂等/重复保护）
    described_class.call(entry: entry.reload)
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(2)
  end

  it 'returns failure for nil / missing entry' do
    expect(described_class.call(entry: nil)).to be_failure
  end
end
