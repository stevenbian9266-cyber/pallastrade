# frozen_string_literal: true

require 'rails_helper'

# PRD-20260906-payments-fin-p4-4 AC-4P4-10: payment_combination.succeeded →
# PaymentCombinationSucceededSubscriber → PostCombinationAllocations
RSpec.describe PallasTrade::FinancialLedger::PaymentCombinationSucceededSubscriber, type: :job do
  let(:store) { @default_store }
  let(:subscriber) { described_class.new }

  def fire_succeeded(combination)
    subscriber.send(:handle, double(payload: { 'id' => combination.prefixed_id }))
  end

  it 'declares subscription to payment_combination.succeeded' do
    expect(described_class.subscription_patterns).to include('payment_combination.succeeded')
  end

  it 'AC-4P4-10 posts ORDER_ALLOCATION entries for a settled txn-ized combination' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
    txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'combined_payment', currency: 'USD',
                                                   amount: 100, payment_combination: combo)
    o1 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 60, total: 60,
                        payment_state: 'balance_due')
    o2 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 40, total: 40,
                        payment_state: 'balance_due')
    s1 = create(:payment_split, payment_combination: combo, order: o1, payment: nil, currency: 'USD', captured_amount: 60)
    s2 = create(:payment_split, payment_combination: combo, order: o2, payment: nil, currency: 'USD', captured_amount: 40)

    expect { fire_succeeded(combo) }.to change(PallasTrade::FinancialLedgerEntry, :count).by(2)
    entries = PallasTrade::FinancialLedgerEntry.where(entry_type: 'ORDER_ALLOCATION')
    expect(entries.map(&:payment_split_id).sort).to eq([s1.id, s2.id].sort)
    expect(entries.sum(:amount).to_d).to eq(100.0)
    expect(entries.map(&:commerce_transaction_id).uniq).to eq([txn.id])

    # 重复触发 → 幂等不新增
    expect { fire_succeeded(combo) }.not_to(change { PallasTrade::FinancialLedgerEntry.count })
  end

  it 'AC-4P4-10 legacy combination without txn → safe no-op (skipped, no raise)' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
    o1 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                        payment_state: 'balance_due')
    create(:payment_split, payment_combination: combo, order: o1, payment: nil, currency: 'USD', captured_amount: 100)

    expect do
      fire_succeeded(combo)
    end.not_to raise_error
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'ORDER_ALLOCATION').count).to eq(0)
  end

  it 'is a safe no-op for an unknown combination id / nil payload' do
    expect do
      subscriber.send(:handle, double(payload: { 'id' => 'pcom_missing' }))
    end.not_to raise_error
    expect do
      subscriber.send(:handle, double(payload: nil))
    end.not_to raise_error
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end
end
