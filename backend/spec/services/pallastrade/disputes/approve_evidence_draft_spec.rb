# frozen_string_literal: true

# PRD-20260913-payments (DSP-P7-10 B2 / FR-005) AC-005 / AC-010
# —— 双人复核：签核 append-only、自己批自己被拒、提交前置校验（缺签核/同人签发均拒绝）、
# 默认开关关闭 → 既有提交路径行为不变；全程零资金副作用。
require 'rails_helper'

RSpec.describe PallasTrade::Disputes::ApproveEvidenceDraft do
  let!(:store) { create(:store, code: "p710_appr_#{SecureRandom.hex(4)}", default: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def make_dispute(state: 'needs_response')
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p710ap@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p710a_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p710a_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd',
      store_id: store.id, payment: payment, order: order
    )
  end

  def stub_catalog
    allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return(
      [{ key: 'customer_name', type: 'text', required: true }, { key: 'receipt', type: 'file' }]
    )
  end

  def stub_write
    allow_any_instance_of(payment_method.class).to receive(:submit_dispute_evidence).and_return(
      { provider_reference: 'dp_appr_written', status: 'under_review', metadata: {} }
    )
  end

  def money_counts
    {
      submissions: PallasTrade::DisputeEvidenceSubmission.count,
      approvals: PallasTrade::DisputeEvidenceApproval.count,
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      orders: PallasTrade::Order.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count
    }
  end

  # ServiceModule 的失败形态是 ResultError（struct），统一取业务码
  def code_of(outcome)
    error = outcome.error
    error.respond_to?(:value) ? error.value.to_s : error.to_s
  end

  describe 'AC-005 签核（approved / rejected）' do
    before do
      stub_catalog
      stub_write
    end

    it 'records an immutable approval bound to the draft digest, with audit' do
      dispute = make_dispute

      outcome = described_class.call(
        dispute: dispute,
        actor: { type: 'PallasTrade::AdminUser', id: 9, label: 'reviewer@example.com' },
        evidence: { 'customer_name' => 'Jane Doe' },
        requested_by: 'preparer@example.com',
        note: 'Checked against the delivery log'
      )

      expect(outcome).to be_success
      approval = outcome.value[:approval]
      expect(approval).to be_persisted
      expect(approval.prefixed_id).to start_with('dap_')
      expect(approval.decision).to eq('approved')
      expect(approval.actor_label).to eq('reviewer@example.com')
      expect(approval.requested_by).to eq('preparer@example.com')
      expect(approval.note).to eq('Checked against the delivery log')
      expect(approval.payload_digest.length).to eq(64)

      # 摘要与提交幂等基准同算法（同一草稿 → 同一摘要）
      preview = PallasTrade::Disputes::PreSubmitCheck.call(dispute: dispute, evidence: { 'customer_name' => 'Jane Doe' })
      expect(approval.payload_digest).to eq(preview.value[:digest])

      expect(PallasTrade::AuditLog.where(action: 'dispute_evidence_draft_approved').count).to eq(1)
    end

    it 'is idempotent for the same reviewer and digest, and records a rejection distinctly' do
      dispute = make_dispute
      actor = { type: 'PallasTrade::AdminUser', id: 9, label: 'reviewer@example.com' }

      first = described_class.call(dispute: dispute, actor: actor, evidence: { 'customer_name' => 'Jane' })
      second = described_class.call(dispute: dispute, actor: actor, evidence: { 'customer_name' => 'Jane' })
      rejected = described_class.call(dispute: dispute, actor: actor, evidence: { 'customer_name' => 'Jane' },
                                      decision: 'rejected', note: 'Missing proof of delivery')

      expect(first.value[:idempotent]).to be(false)
      expect(second.value[:idempotent]).to be(true)
      expect(second.value[:approval].id).to eq(first.value[:approval].id)
      expect(rejected.value[:approval].rejected?).to be(true)
      expect(PallasTrade::DisputeEvidenceApproval.count).to eq(2)
      expect(PallasTrade::AuditLog.where(action: 'dispute_evidence_draft_rejected').count).to eq(1)
      # 仅 approved 能满足提交门禁
      expect(PallasTrade::DisputeEvidenceApproval.approved_for(dispute: dispute, payload_digest: first.value[:approval].payload_digest).decision)
        .to eq('approved')
    end

    it 'refuses self-review (same operator as the preparer)' do
      dispute = make_dispute

      outcome = described_class.call(
        dispute: dispute,
        actor: { type: 'PallasTrade::AdminUser', id: 9, label: 'same@example.com' },
        evidence: { 'customer_name' => 'Jane' },
        requested_by: 'same@example.com'
      )

      expect(outcome).to be_failure
      expect(code_of(outcome)).to eq('approval_requires_different_operator')
      expect(PallasTrade::DisputeEvidenceApproval.count).to eq(0)
    end

    it 'rejects an empty draft, a terminal dispute and an unsupported gateway' do
      dispute = make_dispute
      expect(code_of(described_class.call(dispute: dispute, evidence: {}))).to eq('payload_digest_missing')
      expect(code_of(described_class.call(dispute: make_dispute(state: 'won'),
                                         evidence: { 'customer_name' => 'x' }))).to eq('dispute_terminal')

      allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return([])
      expect(code_of(described_class.call(dispute: dispute, evidence: { 'customer_name' => 'x' })))
        .to eq('evidence_submission_unsupported')
    end
  end

  describe 'AC-005 提交前置校验（SubmitEvidence + require_approval）' do
    before do
      stub_catalog
      stub_write
    end

    it 'blocks the submission when no second-operator approval exists' do
      dispute = make_dispute
      before = money_counts

      expect_any_instance_of(payment_method.class).not_to receive(:submit_dispute_evidence)
      outcome = PallasTrade::Disputes::SubmitEvidence.call(
        dispute: dispute, evidence: { 'customer_name' => 'Jane' }, require_approval: true
      )

      expect(outcome).to be_failure
      expect(code_of(outcome)).to eq('evidence_review_required')
      expect(money_counts).to eq(before)
    end

    it 'lets a different operator submit an approved draft and links the approval to the receipt' do
      dispute = make_dispute
      described_class.call(dispute: dispute,
                           actor: { type: 'PallasTrade::AdminUser', id: 9, label: 'reviewer@example.com' },
                           evidence: { 'customer_name' => 'Jane' })

      outcome = PallasTrade::Disputes::SubmitEvidence.call(
        dispute: dispute, evidence: { 'customer_name' => 'Jane' }, require_approval: true,
        actor: { type: 'PallasTrade::AdminUser', id: 7, label: 'submitter@example.com' }
      )

      expect(outcome).to be_success
      submission = outcome.value[:submission]
      approval = PallasTrade::DisputeEvidenceApproval.first
      expect(submission.response_metadata['approval_id']).to eq(approval.prefixed_id)
      expect(PallasTrade::AuditLog.where(action: 'dispute_evidence_submitted').count).to eq(1)
    end

    it 'refuses when the submitter is the reviewer (approval must come from someone else)' do
      dispute = make_dispute
      described_class.call(dispute: dispute,
                           actor: { type: 'PallasTrade::AdminUser', id: 9, label: 'reviewer@example.com' },
                           evidence: { 'customer_name' => 'Jane' })

      expect_any_instance_of(payment_method.class).not_to receive(:submit_dispute_evidence)
      outcome = PallasTrade::Disputes::SubmitEvidence.call(
        dispute: dispute, evidence: { 'customer_name' => 'Jane' }, require_approval: true,
        actor: { type: 'PallasTrade::AdminUser', id: 9, label: 'reviewer@example.com' }
      )

      expect(outcome).to be_failure
      expect(code_of(outcome)).to eq('approval_requires_different_operator')
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)
    end

    it 'keeps the legacy path untouched when the flag is off (no approval needed)' do
      dispute = make_dispute

      outcome = PallasTrade::Disputes::SubmitEvidence.call(
        dispute: dispute, evidence: { 'customer_name' => 'Jane' }
      )

      expect(outcome).to be_success
      expect(PallasTrade::DisputeEvidenceApproval.count).to eq(0)
      expect(outcome.value[:submission].response_metadata['approval_id']).to be_nil
    end
  end

  describe 'AC-010 铁律：签核不发资金、回执不可改' do
    it 'never touches funds and keeps both records append-only' do
      stub_catalog
      stub_write
      dispute = make_dispute
      before = money_counts.except(:approvals)

      described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane' },
                           actor: { type: 'PallasTrade::AdminUser', id: 9, label: 'reviewer@example.com' })
      approval = PallasTrade::DisputeEvidenceApproval.first

      expect(money_counts.except(:approvals)).to eq(before)
      expect { approval.update!(note: 'tampered') }.to raise_error(PallasTrade::DisputeEvidenceApproval::ImmutableError)
      expect { approval.update_columns(note: 'tampered') }.to raise_error(PallasTrade::DisputeEvidenceApproval::ImmutableError)
    end
  end
end
