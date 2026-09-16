# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13-reconciliation-cases（切片1，core 服务）
#   AC-002 ← FR-002：同步幂等（不重复建案、触碰计数）
#   AC-003 ← FR-002：差异消失 → 自动销案；人工判定不被覆盖
#   AC-004 ← FR-002：签名变化 → 旧案自动销案 + 新案入队
#   AC-009 ← FR-006：零资金副作用（支付/退款/订单/账本行数与金额不变）
RSpec.describe PallasTrade::Reconciliations::SyncCases, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def make_transaction(state: 'completed')
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: store.default_currency.to_s, amount: 100
    )
    tx.start_payment! if tx.state == 'created'
    tx.confirm_payment! if %w[payment_confirmed finalizing completed].include?(state)
    tx.begin_finalizing! if %w[finalizing completed].include?(state)
    tx.complete! if state == 'completed'
    tx
  end

  # captured payment 且**不写 journal** → NEEDS_ATTENTION + JOURNAL_POSTING_MISSING
  def captured_payment(txn:)
    pm = create(:bogus_payment_method, store: store, active: true)
    session = create(:bogus_payment_session, order: order, payment_method: pm, status: 'completed',
                                             amount: 100, currency: 'USD', commerce_transaction: txn)
    payment = create(:payment, order: order, payment_method: pm, amount: 100,
                               state: 'completed', payment_session: session,
                               source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 100.0)
    payment
  end

  def post_cash_entry(txn, payment)
    PallasTrade::FinancialLedgerEntry.create!(
      commerce_transaction: txn, entry_type: 'CASH_CAPTURED', amount: 100.0, currency: 'USD',
      idempotency_key: "spec-d13-#{txn.id}-#{SecureRandom.hex(3)}", effective_at: Time.current,
      payment: payment
    )
  end

  def cases_for(transaction)
    PallasTrade::ReconciliationCase.where(transaction_id: transaction.id)
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-002
  it 'opens one case for a journal-missing transaction and touches it on repeat runs' do
    txn = make_transaction
    captured_payment(txn: txn)

    first = described_class.call(transaction: txn)
    expect(first.success?).to be(true)
    expect(first.value[:opened].size).to eq(1)

    case_record = cases_for(txn).sole
    expect(case_record.kind).to eq('transaction')
    expect(case_record.status).to eq('open')
    expect(case_record.difference_type).to eq('journal_missing')
    expect(case_record.severity).to eq('attention')
    expect(case_record.reason_codes).to include('JOURNAL_POSTING_MISSING')
    expect(case_record.occurrences).to eq(1)
    expect(case_record.store_id).to eq(store.id)
    expect(case_record.commerce_transaction).to eq(txn)
    expect(case_record.provider).to eq('bogus')

    second = described_class.call(transaction: txn)
    expect(second.value[:touched].size).to eq(1)
    expect(second.value[:opened]).to be_empty
    expect(cases_for(txn).count).to eq(1)
    expect(case_record.reload.occurrences).to eq(2)
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-003
  it 'auto-closes the case when the difference disappears' do
    txn = make_transaction
    payment = captured_payment(txn: txn)
    described_class.call(transaction: txn)

    post_cash_entry(txn, payment)

    result = described_class.call(transaction: txn)
    expect(result.value[:closed].size).to eq(1)

    case_record = cases_for(txn).sole.reload
    expect(case_record.status).to eq('fixed')
    expect(case_record.resolution_source).to eq('auto')
    expect(case_record.resolved_at).to be_present
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-003
  it 'never overwrites a human decision' do
    txn = make_transaction
    captured_payment(txn: txn)
    described_class.call(transaction: txn)

    case_record = cases_for(txn).sole
    case_record.close!(status: 'dismissed', source: 'human', note: 'known duplicate alert')

    result = described_class.call(transaction: txn)

    expect(result.value[:opened]).to be_empty
    expect(result.value[:closed]).to be_empty
    expect(case_record.reload.status).to eq('dismissed')
    expect(case_record.resolution_source).to eq('human')
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-004
  it 'closes a superseded case when the signature changes' do
    txn = make_transaction
    payment = captured_payment(txn: txn)

    stale = PallasTrade::ReconciliationCase.create!(
      store: store, kind: 'transaction', commerce_transaction: txn, status: 'open',
      difference_type: 'needs_attention', severity: 'attention',
      dedupe_key: PallasTrade::ReconciliationCase.dedupe_key_for(transaction_id: txn.id,
                                                                 signature: 'OLD_SIGNATURE'),
      detected_at: 1.hour.ago, last_seen_at: 1.hour.ago
    )

    described_class.call(transaction: txn)

    expect(stale.reload.status).to eq('fixed')
    expect(stale.resolution_source).to eq('auto')
    expect(stale.resolution_note).to include('Superseded')

    current = cases_for(txn).open_queue.sole
    expect(current.dedupe_key).not_to eq(stale.dedupe_key)

    # 再补账本 → 新签名也应被自动销案（队列不残留陈旧项）
    post_cash_entry(txn, payment)
    described_class.call(transaction: txn)
    expect(current.reload.status).to eq('fixed')
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-002
  it 'writes an audit entry when the queue changes' do
    txn = make_transaction
    captured_payment(txn: txn)

    expect { described_class.call(transaction: txn) }.
      to change { PallasTrade::AuditLog.where(action: 'reconciliation_cases_synced').count }.by(1)
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-009
  it 'has zero money side effects' do
    txn = make_transaction
    captured_payment(txn: txn)

    snapshot = lambda do
      {
        payments: PallasTrade::Payment.count,
        refunds: PallasTrade::Refund.count,
        orders: PallasTrade::Order.count,
        entries: PallasTrade::FinancialLedgerEntry.count,
        total: PallasTrade::FinancialLedgerEntry.sum(:amount).to_s,
        payment_state: PallasTrade::Payment.order(:id).last&.state,
        txn_state: txn.reload.state
      }
    end

    before = snapshot.call
    described_class.call(transaction: txn)
    described_class.call(transaction: txn)

    expect(snapshot.call).to eq(before)
    expect(PallasTrade::ReconciliationCase.count).to eq(1)
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-002
  it 'fails gracefully without a transaction' do
    result = described_class.call(transaction: nil)

    expect(result.success?).to be(false)
    expect(PallasTrade::ReconciliationCase.count).to eq(0)
  end
end
