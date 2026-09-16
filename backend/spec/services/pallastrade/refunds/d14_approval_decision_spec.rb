# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14-refund-approval（切片1，core 服务）
#   AC-004 ← FR-003：第二人批准 → 执行入队；同人自批被拒；重复批准幂等；终态互斥
#   AC-004 ← FR-003：拒绝（必填原因）→ `cancel_request`（额度释放）+ 审计
#   AC-008 ← FR-007：零资金副作用（不走 provider；只改 durable 行与审批行）
RSpec.describe 'Refund approvals decision (D14)', type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 200, total: 200,
                   payment_state: 'balance_due')
  end
  let(:payment) do
    create(:payment, order: order, amount: 200, state: 'completed', response_code: 'ch_d14_decision')
  end
  let(:reason) { create(:refund_reason) }

  before do
    # 真实 Sidekiq adapter（仓库约定）：入队以 stub 观测，不用 ActiveJob matcher
    allow(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later)
  end

  def pending_approval(requester_id: 7, amount: 150)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      'refund_policy' => { 'enabled' => true, 'auto_approve_limit' => '100', 'currency' => nil }
    ))
    store.reload
    outcome = PallasTrade::Refunds::Submit.call(payment: payment, amount: amount, reason: reason,
                                                refunder_id: requester_id)
    outcome.value.approval
  end

  # PRD-20260916-payments-d14-refund-approval AC-004
  it 'executes the refund only after a different person approves it' do
    approval = pending_approval(requester_id: 7)

    result = PallasTrade::Refunds::Approvals::Approve.call(approval: approval, approver_id: 9)

    expect(result.success?).to be(true)
    expect(result.value.status).to eq('approved')
    expect(result.value.approver_id).to eq(9)
    expect(result.value.decided_at).to be_present
    expect(PallasTrade::Refunds::ExecuteJob).to have_received(:perform_later).with(approval.refund_id)

    expect(approval.reload).to be_approved
    audit = PallasTrade::AuditLog.find_by(action: 'refund_approval_approved')
    expect(audit.metadata['approver_id']).to eq(9)
    expect(audit.metadata['enqueued']).to be(true)
  end

  # PRD-20260916-payments-d14-refund-approval AC-004（职责分离）
  it 'refuses self-approval and self-rejection' do
    approval = pending_approval(requester_id: 7)

    result = PallasTrade::Refunds::Approvals::Approve.call(approval: approval, approver_id: 7)
    expect(result.success?).to be(false)
    expect(result.error.to_s).to eq('approver_must_differ')
    expect(PallasTrade::Refunds::ExecuteJob).not_to have_received(:perform_later)

    expect(approval.reload).to be_pending

    reject = PallasTrade::Refunds::Approvals::Reject.call(approval: approval, approver_id: 7, note: 'mine')
    expect(reject.success?).to be(false)
    expect(reject.error.to_s).to eq('approver_must_differ')
    expect(approval.reload).to be_pending

    missing = PallasTrade::Refunds::Approvals::Approve.call(approval: approval, approver_id: nil)
    expect(missing.error.to_s).to eq('approver_required')
  end

  # PRD-20260916-payments-d14-refund-approval AC-004（幂等 + 终态互斥）
  it 'is idempotent on repeat approval and mutually exclusive with rejection' do
    approval = pending_approval(requester_id: 7)

    PallasTrade::Refunds::Approvals::Approve.call(approval: approval, approver_id: 9, note: 'ok')

    second = PallasTrade::Refunds::Approvals::Approve.call(approval: approval, approver_id: 9)
    expect(second.success?).to be(true)
    expect(second.value.id).to eq(approval.id)
    expect(PallasTrade::Refunds::ExecuteJob).to have_received(:perform_later).once

    rejected = PallasTrade::Refunds::Approvals::Reject.call(approval: approval, approver_id: 9, note: 'too late')
    expect(rejected.success?).to be(false)
    expect(rejected.error.to_s).to eq('approval_already_approved')
  end

  # PRD-20260916-payments-d14-refund-approval AC-004（拒绝 → 释放额度）
  it 'cancels the refund request on rejection and requires a reason' do
    approval = pending_approval(requester_id: 7)
    refund = approval.refund

    blank_note = PallasTrade::Refunds::Approvals::Reject.call(approval: approval, approver_id: 9, note: '  ')
    expect(blank_note.success?).to be(false)
    expect(blank_note.error.to_s).to eq('note_required')
    expect(refund.reload.state).to eq('requested')

    result = PallasTrade::Refunds::Approvals::Reject.call(approval: approval, approver_id: 9, note: 'not our policy')
    expect(result.success?).to be(true)

    expect(approval.reload).to be_rejected
    expect(approval.note).to eq('not our policy')
    expect(refund.reload.state).to eq('canceled')
    audit = PallasTrade::AuditLog.find_by(action: 'refund_approval_rejected')
    expect(audit.metadata['refund_canceled']).to be(true)

    # 幂等：重复拒绝返回现状
    again = PallasTrade::Refunds::Approvals::Reject.call(approval: approval, approver_id: 9, note: 'again')
    expect(again.success?).to be(true)
    expect(again.value.id).to eq(approval.id)
  end

  # PRD-20260916-payments-d14-refund-approval AC-008（零资金副作用）
  it 'never calls the provider and leaves payment/journal untouched' do
    approval = pending_approval(requester_id: 7)
    before = {
      payments: PallasTrade::Payment.count, ledger: PallasTrade::FinancialLedgerEntry.count,
      amount: payment.reload.amount.to_d, state: payment.state
    }

    PallasTrade::Refunds::Approvals::Approve.call(approval: approval, approver_id: 9)

    # 只入队（provider I/O 归 ExecuteJob）；本服务不改资金对象
    expect(PallasTrade::Refunds::ExecuteJob).to have_received(:perform_later).with(approval.refund_id)
    expect(
      payments: PallasTrade::Payment.count, ledger: PallasTrade::FinancialLedgerEntry.count,
      amount: payment.reload.amount.to_d, state: payment.state
    ).to eq(before)

    expect(PallasTrade::Refunds::Approvals::Approve.call(approval: nil, approver_id: 9).error.to_s)
      .to eq('approval_not_found')
  end
end
