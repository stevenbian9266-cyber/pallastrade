# frozen_string_literal: true

# PRD-20260913-payments (DSP-P7-10 B1) AC-002 / AC-003 / AC-010
# —— 提交前完整性/合规校验：阻断项可辨识、修复建议齐备、**零写**（不建回执、不写审计、不触网）。
require 'rails_helper'

RSpec.describe PallasTrade::Disputes::PreSubmitCheck do
  let!(:store) { create(:store, code: "p710_precheck_#{SecureRandom.hex(4)}", default: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def make_dispute(state: 'needs_response', evidence_due_at: nil)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p710pc@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p710pc_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_p710pc_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd',
      evidence_due_at: evidence_due_at,
      store_id: store.id, payment: payment, order: order
    )
  end

  def stub_catalog(required: true)
    allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return(
      [{ key: 'customer_name', type: 'text', max_length: 10, required: required },
       { key: 'receipt', type: 'file' }]
    )
  end

  def write_counts
    { submissions: PallasTrade::DisputeEvidenceSubmission.count, audits: PallasTrade::AuditLog.count,
      events_note: PallasTrade::Payment.count }
  end

  describe 'AC-003 阻断项可辨识' do
    before { stub_catalog }

    it 'blocks with evidence_submission_unsupported when the provider declares no catalog' do
      allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return([])
      outcome = described_class.call(dispute: make_dispute, evidence: { 'customer_name' => 'Jane' })

      expect(outcome).to be_success
      expect(outcome.value[:ok]).to be(false)
      expect(outcome.value[:supported]).to be(false)
      expect(outcome.value[:blocking]).to include('evidence_submission_unsupported')
    end

    it 'reports empty / unknown / missing-required / too-long payloads distinctly' do
      empty = described_class.call(dispute: make_dispute, evidence: {}).value
      expect(empty[:ok]).to be(false)
      expect(empty[:blocking]).to include('evidence_empty')
      expect(empty[:fix_hints]['evidence_empty']).to eq('fill_at_least_one_field')

      unknown = described_class.call(dispute: make_dispute,
                                     evidence: { 'customer_name' => 'Jane', 'what' => 'x' }).value
      expect(unknown[:blocking]).to include('unknown_evidence_key:what')
      expect(unknown[:unknown_keys]).to eq(['what'])

      too_long = described_class.call(dispute: make_dispute,
                                      evidence: { 'customer_name' => 'x' * 11 }).value
      expect(too_long[:blocking]).to include('evidence_too_long:customer_name')
      expect(too_long[:fix_hints]['evidence_too_long:customer_name']).to eq('shorten_text')
    end

    it 'treats a required key left empty as a missing-required blocking item' do
      outcome = described_class.call(dispute: make_dispute, evidence: { 'customer_name' => '' }).value

      expect(outcome[:blocking]).to include('evidence_empty')
      expect(outcome[:missing_required]).to eq(['customer_name'])
      expect(outcome[:provided_keys]).to eq([])
    end

    it 'is ok when every rule is satisfied' do
      outcome = described_class.call(dispute: make_dispute, evidence: { 'customer_name' => 'Jane' })

      expect(outcome.value[:ok]).to be(true)
      expect(outcome.value[:blocking]).to be_empty
      expect(outcome.value[:digest].to_s.length).to eq(64)
    end

    it 'marks unknown state (nil dispute) instead of raising' do
      outcome = described_class.call(dispute: nil, evidence: {})

      expect(outcome.value[:blocking]).to include('dispute_not_found')
    end

    it 'blocks terminal disputes' do
      outcome = described_class.call(dispute: make_dispute(state: 'won'), evidence: { 'customer_name' => 'Jane' }).value

      expect(outcome[:blocking]).to include('dispute_terminal')
    end
  end

  describe 'AC-003 逾期判定（需二次确认）' do
    before { stub_catalog }

    it 'blocks a late payload until accept_late is given, then only warns' do
      dispute = make_dispute(evidence_due_at: 2.days.ago)

      blocked = described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane' }).value
      expect(blocked[:late]).to be(true)
      expect(blocked[:blocking]).to include('late_submission_requires_confirmation')
      expect(blocked[:fix_hints]['late_submission_requires_confirmation']).to eq('confirm_late_submission')

      confirmed = described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane' },
                                       accept_late: true).value
      expect(confirmed[:ok]).to be(true)
      expect(confirmed[:warnings]).to include('evidence_deadline_passed')
    end
  end

  describe 'AC-010 铁律：预检零写、零 provider 调用' do
    before { stub_catalog }

    it 'does not touch receipts, audits, funds, or the provider write contract' do
      dispute = make_dispute(evidence_due_at: 2.days.ago)
      before = write_counts

      expect_any_instance_of(payment_method.class).not_to receive(:submit_dispute_evidence)
      described_class.call(dispute: dispute, evidence: { 'customer_name' => 'x' * 50 })

      expect(write_counts).to eq(before)
      expect(dispute.reload.evidence_submitted_at).to be_nil
    end
  end
end
