# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-4 AC-4P4-01/02/06/10
require 'rails_helper'

RSpec.describe PallasTrade::FinancialLedger::PostCombinationAllocations, type: :service do
  let(:store) { @default_store }

  def make_combination(amount: 100, txn: true, status: 'pending')
    combo = create(:payment_combination, store: store, currency: 'USD', amount: amount, status: status)
    if txn
      PallasTrade::CommerceTransaction.create!(store: store, purpose: 'combined_payment', currency: 'USD',
                                               amount: amount, payment_combination: combo)
    end
    combo
  end

  def make_order(total)
    create(:order, store: store, state: 'pending', status: 'placed', item_total: total, total: total,
                   payment_state: 'balance_due')
  end

  # 构造已入账（captured）的 splits——等价 Settlement 后状态
  def add_captured_split(combo:, captured:)
    order = make_order(captured)
    create(:payment_split, payment_combination: combo, order: order, payment: nil,
                           currency: 'USD', captured_amount: captured)
  end

  def post_all!(combo)
    described_class.call(combination: combo)
  end

  it 'AC-4P4-01 posts one ORDER_ALLOCATION per captured split (2 members → 2 entries)' do
    combo = make_combination(amount: 100)
    s1 = add_captured_split(combo: combo, captured: 60)
    s2 = add_captured_split(combo: combo, captured: 40)

    result = post_all!(combo)
    expect(result).to be_success
    expect(result.value[:posted]).to eq(2)
    expect(result.value[:skipped]).to eq(0)

    entries = PallasTrade::FinancialLedgerEntry.where(entry_type: 'ORDER_ALLOCATION')
    expect(entries.count).to eq(2)
    expect(entries.map(&:payment_split_id).sort).to eq([s1.id, s2.id].sort)
    expect(entries.sum(:amount).to_d).to eq(100.0)
  end

  it 'AC-4P4-06 is idempotent: rerun produces no new entries' do
    combo = make_combination(amount: 100)
    add_captured_split(combo: combo, captured: 60)
    add_captured_split(combo: combo, captured: 40)

    post_all!(combo)
    expect { post_all!(combo) }.not_to(change { PallasTrade::FinancialLedgerEntry.count })
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'ORDER_ALLOCATION').count).to eq(2)
  end

  it 'AC-4P4-08 legacy combination without txn → all splits skipped (no entries, no failure)' do
    combo = make_combination(txn: false)
    add_captured_split(combo: combo, captured: 60)
    add_captured_split(combo: combo, captured: 40)

    result = post_all!(combo)
    expect(result).to be_success
    expect(result.value[:posted]).to eq(0)
    expect(result.value[:skipped]).to eq(2)
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'ORDER_ALLOCATION').count).to eq(0)
  end

  it 'AC-4P4-10 nil combination → failure' do
    result = described_class.call(combination: nil)
    expect(result).to be_failure
  end

  # AC-4P4-01/02 真实路径：PaymentCombinations::Settlement（生产 primitive）succeed →
  # PostCombinationAllocations → Integrity balanced
  describe 'real Settlement path (AC-4P4-01/02)' do
    let!(:store_i) { create(:store, code: 'p4_alloc_integ_store') }
    let(:user) { create(:user) }
    let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store_i) }

    def unpaid_order
      order = create(:order_with_line_items, store: store_i, user: user, shipment_cost: 0)
      order.shipments.each do |s|
        s.shipping_rates.destroy_all
        s.add_shipping_method(create(:free_shipping_method), true)
      end
      order.next until order.payment? || order.complete? || order.errors.any?
      order.update_columns(state: 'cart', completed_at: nil)
      order.line_items.reload
      PallasTrade::OrderUpdater.new(order).update
      order.reload
      order
    end

    it 'settles a txn-ized combination → per-split ORDER_ALLOCATION posted and balanced' do
      order1 = unpaid_order
      order2 = unpaid_order
      amount = (order1.amount_due + order2.amount_due).to_f
      combo = create(:payment_combination, store: store_i, customer: user, amount: amount, currency: 'USD')
      PallasTrade::CommerceTransaction.create!(store: store_i, purpose: 'combined_payment', currency: 'USD',
                                               amount: amount, payment_combination: combo)
      create(:payment_split, payment_combination: combo, order: order1, payment: nil)
      create(:payment_split, payment_combination: combo, order: order2, payment: nil)
      session = create(:bogus_payment_session, order: order1, payment_method: payment_method,
                                               amount: amount, payment_combination: combo)

      settle = PallasTrade::Payments::PaymentCombinations::Settlement.call(combination: combo,
                                                                            payment_session: session)
      expect(settle).to be_success
      expect(combo.reload).to be_succeeded
      expect(combo.payment_splits.map { |s| s.captured_amount.to_f }.sum).to eq(amount)

      result = described_class.call(combination: combo)
      expect(result).to be_success
      expect(result.value[:posted]).to eq(combo.payment_splits.count)

      integrity = PallasTrade::FinancialLedger::AllocationIntegrity.call(combination: combo).value
      expect(integrity[:split_captured_total]).to eq(amount)
      expect(integrity[:allocation_total]).to eq(integrity[:split_captured_total])
      expect(integrity[:balanced?]).to be(true)
    end
  end
end
