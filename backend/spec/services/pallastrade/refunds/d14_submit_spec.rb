# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14-refund-approval（切片1，core 服务）
#   AC-002 ← FR-002：阈值内 → 自动执行（入队 ExecuteJob）+ 审计 `refund_auto_approved`，不建审批行
#   AC-003 ← FR-002：超阈值 → durable 落库但**不入队** + `RefundApproval(pending)` + 审计
#   AC-003 ← FR-002：策略未启用 → 行为与今天一致（入队、无审批行、无额外审计）
#   AC-005 ← FR-004：同 `request_key` 重复提交只产生一笔退款
#   AC-008 ← FR-007：零资金副作用（Payment/Journal/订单不变；不调 provider）
RSpec.describe PallasTrade::Refunds::Submit, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 200, total: 200,
                   payment_state: 'balance_due')
  end
  let(:payment) do
    create(:payment, order: order, amount: 200, state: 'completed', response_code: 'ch_d14_submit')
  end
  let(:reason) { create(:refund_reason) }

  def enable_policy(limit:, currency: nil)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      'refund_policy' => { 'enabled' => true, 'auto_approve_limit' => limit.to_s, 'currency' => currency }
    ))
    store.reload
  end

  before do
    # 真实 Sidekiq adapter（仓库约定）：入队以 stub 观测，不用 ActiveJob matcher
    allow(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later)
  end

  # PRD-20260916-payments-d14-refund-approval AC-003（策略未启用 = 今天的行为）
  it 'behaves exactly as before when the policy is off' do
    outcome = described_class.call(payment: payment, amount: 50, reason: reason, refunder_id: 1)

    expect(outcome.success?).to be(true)
    expect(outcome.value.state).to eq('requested')
    expect(outcome.value.approval).to be_nil
    expect(PallasTrade::Refunds::ExecuteJob).to have_received(:perform_later).with(outcome.value.id)

    expect(PallasTrade::RefundApproval.count).to eq(0)
    expect(PallasTrade::AuditLog.where(action: %w[refund_auto_approved refund_approval_requested]).count).to eq(0)
  end

  # PRD-20260916-payments-d14-refund-approval AC-002
  it 'auto-approves at or below the limit, audits it and never queues an approval' do
    enable_policy(limit: 100)

    outcome = described_class.call(payment: payment, amount: 100, reason: reason, refunder_id: 1)

    expect(outcome.success?).to be(true)
    expect(outcome.value.state).to eq('requested')
    expect(PallasTrade::Refunds::ExecuteJob).to have_received(:perform_later).with(outcome.value.id)

    expect(PallasTrade::RefundApproval.count).to eq(0)
    audit = PallasTrade::AuditLog.find_by(action: 'refund_auto_approved')
    expect(audit).to be_present
    expect(audit.metadata['policy']).to include('auto_approve_limit' => '100.0')
  end

  # PRD-20260916-payments-d14-refund-approval AC-003
  it 'holds anything above the limit: durable refund, no execution, pending approval' do
    enable_policy(limit: 100, currency: 'USD')

    outcome = described_class.call(payment: payment, amount: 100.01, reason: reason, refunder_id: 7)

    refund = outcome.value
    expect(outcome.success?).to be(true)
    expect(refund).to be_persisted
    expect(refund.state).to eq('requested')
    expect(refund.approval).to be_pending
    expect(refund.approval.requester_id).to eq(7)
    expect(refund.approval.amount.to_d).to eq(100.01.to_d)
    expect(refund.approval.store_id).to eq(store.id)
    expect(refund.approval.policy_limit).to eq('100.0')
    expect(PallasTrade::Refunds::ExecuteJob).not_to have_received(:perform_later)

    expect(PallasTrade::AuditLog.find_by(action: 'refund_approval_requested')).to be_present
  end

  # PRD-20260916-payments-d14-refund-approval AC-003（币种不在策略范围）
  it 'skips the gate when the policy is scoped to another currency' do
    enable_policy(limit: 10, currency: 'EUR')

    outcome = described_class.call(payment: payment, amount: 150, reason: reason, refunder_id: 1)

    expect(outcome.success?).to be(true)
    expect(PallasTrade::RefundApproval.count).to eq(0)
    expect(PallasTrade::Refunds::ExecuteJob).to have_received(:perform_later).with(outcome.value.id)
  end

  # PRD-20260916-payments-d14-refund-approval AC-005
  it 'is idempotent on request_key: a repeated submit reuses the same refund' do
    enable_policy(limit: 100)

    first = described_class.call(payment: payment, amount: 150, reason: reason, refunder_id: 7,
                                 request_key: 'rk_d14_submit')
    second = described_class.call(payment: payment, amount: 150, reason: reason, refunder_id: 7,
                                  request_key: 'rk_d14_submit')

    expect(first.success?).to be(true)
    expect(second.success?).to be(true)
    expect(second.value.id).to eq(first.value.id)
    expect(PallasTrade::Refund.where(request_key: 'rk_d14_submit').count).to eq(1)
    expect(PallasTrade::RefundApproval.count).to eq(1)
    expect(PallasTrade::AuditLog.where(action: 'refund_approval_requested').count).to eq(1)
  end

  # PRD-20260916-payments-d14-refund-approval AC-005
  it 'passes the request key through even when no approval is required' do
    outcome = described_class.call(payment: payment, amount: 10, reason: reason, refunder_id: 1,
                                   request_key: 'rk_d14_plain')

    expect(outcome.value.request_key).to eq('rk_d14_plain')
    expect(PallasTrade::Refund.where(request_key: 'rk_d14_plain').count).to eq(1)
  end

  # PRD-20260916-payments-d14-refund-approval AC-008（零资金副作用 + 校验失败原样传递）
  it 'never touches money state and surfaces validation failures as-is' do
    enable_policy(limit: 100, currency: 'USD')
    payment # 先实例化（避免快照早于创建）
    before = {
      payments: PallasTrade::Payment.count, ledger: PallasTrade::FinancialLedgerEntry.count,
      amount: payment.reload.amount.to_d, state: payment.state
    }

    described_class.call(payment: payment, amount: 150, reason: reason, refunder_id: 7)

    # 超额退款（超过可退额）→ 失败且不落库、不建审批
    failed = described_class.call(payment: payment, amount: 10_000, reason: reason, refunder_id: 7)
    expect(failed.success?).to be(false)
    expect(failed.value).to be_a(PallasTrade::Refund)
    expect(failed.value.errors[:amount]).to be_present
    expect(PallasTrade::Refund.where(payment_id: payment.id).where('amount > ?', 1_000).count).to eq(0)

    expect(
      payments: PallasTrade::Payment.count, ledger: PallasTrade::FinancialLedgerEntry.count,
      amount: payment.reload.amount.to_d, state: payment.state
    ).to eq(before)
    expect(described_class.call(payment: nil, amount: 1).success?).to be(false)
  end
end
