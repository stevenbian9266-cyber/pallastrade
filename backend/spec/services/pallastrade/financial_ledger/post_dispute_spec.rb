# frozen_string_literal: true

require 'rails_helper'

# PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile
# AC-P73-01/02/03/05/06/07/08 —— `FinancialLedger::PostDispute` 编排：
#   ResolveDispute → 门禁 → Post（幂等）；唯一写 = FinancialLedgerEntry。
RSpec.describe PallasTrade::FinancialLedger::PostDispute, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end
  let(:txn) { PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100) }

  def make_dispute(**attrs)
    defaults = { state: 'needs_response', provider_status: 'needs_response', funds_withdrawn_at: nil,
                 funds_reinstated_at: nil, amount: 12.34, transaction: txn, reference: nil }
    values = defaults.merge(attrs)

    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: values[:reference] || "dp_#{SecureRandom.hex(4)}",
      state: values[:state],
      amount: values[:amount],
      currency: 'usd',
      private_metadata: { 'provider_status' => values[:provider_status] },
      funds_withdrawn_at: values[:funds_withdrawn_at],
      funds_reinstated_at: values[:funds_reinstated_at],
      commerce_transaction: values[:transaction],
      payment: payment
    )
  end

  def post!(dispute, fact_type: nil)
    described_class.call(dispute: dispute, fact_type: fact_type)
  end

  it 'AC-P73-01 withdrawn → 恰好 1 条 DISPUTE_FUNDS_WITHDRAWN（负数、dispute_id 溯源、provider 引用）' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)

    result = post!(dispute)
    expect(result).to be_success
    payload = result.value
    expect(payload[:skipped]).to be(false)

    entry = payload[:entry]
    expect(entry).to be_a(PallasTrade::FinancialLedgerEntry)
    expect(entry.entry_type).to eq('DISPUTE_FUNDS_WITHDRAWN')
    expect(entry.amount.to_d).to eq(-12.34.to_d)
    expect(entry.currency.to_s.upcase).to eq('USD')
    expect(entry.state).to eq('posted')
    expect(entry.dispute).to eq(dispute)
    expect(entry.payment).to eq(payment)
    expect(entry.commerce_transaction).to eq(txn)
    expect(entry.provider_reference).to eq(dispute.provider_dispute_reference)
    expect(entry.effective_at).to eq(dispute.funds_withdrawn_at)
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FUNDS_WITHDRAWN').count).to eq(1)
  end

  it 'AC-P73-02 幂等：重复 PostDispute → 同一行，绝不重复入账' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)

    first = post!(dispute).value[:entry]
    second = post!(dispute).value[:entry]

    expect(second.id).to eq(first.id)
    expect(PallasTrade::FinancialLedgerEntry.where(dispute_id: dispute.id).count).to eq(1)
  end

  it 'AC-P73-03 同 payment 两笔争议（同秒同额）→ 2 条独立 entry（修复 posting key 碰撞）' do
    at = Time.current.change(usec: 0)
    first = make_dispute(funds_withdrawn_at: at, reference: 'dp_first')
    second = make_dispute(funds_withdrawn_at: at, reference: 'dp_second')

    e1 = post!(first).value[:entry]
    e2 = post!(second).value[:entry]

    expect(e1.id).not_to eq(e2.id)
    expect(e1.dispute).to eq(first)
    expect(e2.dispute).to eq(second)
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FUNDS_WITHDRAWN').count).to eq(2)
  end

  it 'AC-P73-04 争议胜诉：扣回 + 返还各一条，净额 0；DISPUTE_WON 本身不产生账行' do
    dispute = make_dispute(state: 'won', provider_status: 'won',
                           funds_withdrawn_at: 3.days.ago, funds_reinstated_at: 1.day.ago)

    withdrawn = post!(dispute, fact_type: 'DISPUTE_FUNDS_WITHDRAWN').value[:entry]
    reinstated = post!(dispute, fact_type: 'DISPUTE_FUNDS_REINSTATED').value[:entry]
    terminal = post!(dispute)

    expect(withdrawn.amount.to_d).to eq(-12.34.to_d)
    expect(reinstated.amount.to_d).to eq(12.34.to_d)
    expect(withdrawn.amount.to_d + reinstated.amount.to_d).to eq(0.to_d)
    expect(terminal.value[:skipped]).to be(true)
    expect(terminal.value[:reason]).to eq('entry_type_not_activated')
    expect(PallasTrade::FinancialLedgerEntry.where(dispute_id: dispute.id).count).to eq(2)
  end

  it 'AC-P73-05 非现金事实（opened）→ skip entry_type_not_activated，零账行' do
    result = post!(make_dispute)

    expect(result.value[:skipped]).to be(true)
    expect(result.value[:reason]).to eq('entry_type_not_activated')
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-P73-06 事实不可证（金额 0 → AMBIGUOUS）→ skip fact_status_not_confirmed，零账行' do
    result = post!(make_dispute(funds_withdrawn_at: Time.current, amount: 0))

    expect(result.value[:skipped]).to be(true)
    expect(result.value[:reason]).to eq('fact_status_not_confirmed')
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-P73-07 无 txn → commerce_transaction_missing；缺资金时间戳 → effective_at_missing' do
    no_txn = post!(make_dispute(funds_withdrawn_at: Time.current, transaction: nil))
    expect(no_txn.value[:reason]).to eq('commerce_transaction_missing')

    no_timestamp = post!(make_dispute, fact_type: 'DISPUTE_FUNDS_WITHDRAWN')
    expect(no_timestamp.value[:reason]).to eq('effective_at_missing')

    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-P73-08 只读边界：入账不改 dispute/payment/txn，只新增 1 条账行' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)
    dispute_before = dispute.reload.attributes
    payments_before = PallasTrade::Payment.count
    txns_before = PallasTrade::CommerceTransaction.count
    entries_before = PallasTrade::FinancialLedgerEntry.count

    expect(dispute).not_to receive(:save)
    expect(dispute).not_to receive(:update)

    expect(post!(dispute)).to be_success

    expect(dispute.reload.attributes).to eq(dispute_before)
    expect(PallasTrade::Payment.count).to eq(payments_before)
    expect(PallasTrade::CommerceTransaction.count).to eq(txns_before)
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(entries_before + 1)
  end
end
