# frozen_string_literal: true

# PRD-20260913-payments-dsp-p7-8-dispute-dangerous-actions-and-evidence-submission
# AC-P78-01/02/03/04/05/10/11/12 —— 提交证据编排：目录校验、provider 写、不可变回执、幂等、
# 逾期策略、事件、铁律负向断言（零资金副作用）。
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe PallasTrade::Disputes::SubmitEvidence do
  let!(:store) { create(:store, code: "p78_submit_#{SecureRandom.hex(4)}", default: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def make_dispute(state: 'needs_response', evidence_due_at: nil)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p78@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p78_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_p78_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd',
      evidence_due_at: evidence_due_at,
      store_id: store.id, payment: payment, order: order
    )
  end

  # provider 写契约打桩（类级：服务内会重新载入 dispute → 实例级 stub 会失效）
  def stub_write(status: 'under_review', reference: 'dp_written', raise_error: nil)
    if raise_error
      allow_any_instance_of(payment_method.class).to receive(:submit_dispute_evidence).and_raise(raise_error)
    else
      allow_any_instance_of(payment_method.class).to receive(:submit_dispute_evidence).and_return(
        { provider_reference: reference, status: status, metadata: { 'evidence_keys' => %w[customer_name] } }
      )
    end
  end

  def stub_catalog
    allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return(
      [{ key: 'customer_name', type: 'text' }, { key: 'product_description', type: 'text' },
       { key: 'receipt', type: 'file' }]
    )
  end

  def money_counts
    {
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      orders: PallasTrade::Order.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count,
      inventory_units: PallasTrade::InventoryUnit.count,
      stock_reservations: PallasTrade::StockReservation.count
    }
  end

  def temp_evidence_file
    file = Tempfile.new(['evidence', '.png'])
    file.binmode
    file.write("\x89PNG\r\n\x1a\n".b)
    file.rewind
    file
  end

  describe 'AC-P78-03 成功提交' do
    it 'writes to the provider, records an immutable receipt, audits and publishes' do
      stub_catalog
      stub_write(status: 'under_review')
      dispute = make_dispute

      before_counts = money_counts
      expect(PallasTrade::Events).to receive(:publish).with(
        'dispute.evidence_submitted', hash_including(dispute_id: dispute.prefixed_id), anything
      ).and_call_original

      outcome = described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane Doe' },
                                     actor: { type: 'PallasTrade::AdminUser', id: 7, label: 'ops@example.com' })

      expect(outcome).to be_success
      submission = outcome.value[:submission]
      expect(submission).to be_persisted
      expect(submission.kind).to eq('evidence_submitted')
      expect(submission.provider_status).to eq('under_review')
      expect(submission.provider_reference).to eq('dp_written')
      expect(submission.actor_label).to eq('ops@example.com')
      expect(submission.late).to be(false)
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(1)

      # 审计（danger 三件套之一）
      expect(PallasTrade::AuditLog.where(action: 'dispute_evidence_submitted').count).to eq(1)

      # AC-P78-12：零资金/订单/库存副作用
      expect(money_counts).to eq(before_counts)
    end
  end

  describe 'AC-P78-04 幂等' do
    it 'does not call the provider twice for the same payload' do
      stub_catalog
      stub_write
      dispute = make_dispute

      # AC-P78-11：事件恰好一次（幂等重放不再发布）
      expect(PallasTrade::Events).to receive(:publish).once.with(
        'dispute.evidence_submitted', hash_including(dispute_id: dispute.prefixed_id), anything
      ).and_call_original

      first = described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane' })
      expect(first).to be_success
      expect(first.value[:idempotent]).to be(false)

      second = described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane' })
      expect(second).to be_success
      expect(second.value[:idempotent]).to be(true)
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(1)
    end
  end

  describe 'AC-P78-05 provider 失败' do
    it 'returns failure, writes no receipt and leaves an audit trail' do
      stub_catalog
      stub_write(raise_error: PallasTrade::Core::GatewayError.new('boom'))
      dispute = make_dispute

      outcome = described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane' })

      expect(outcome).not_to be_success
      expect(outcome.error.to_s).to include('provider_error')
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)
      expect(PallasTrade::AuditLog.where(action: 'dispute_evidence_submit_failed').count).to eq(1)
    end
  end

  describe 'AC-P78-02 目录校验' do
    it 'rejects unknown keys and empty payloads without calling the provider' do
      stub_catalog
      allow_any_instance_of(payment_method.class).to receive(:submit_dispute_evidence).and_raise('provider must not be called')
      dispute = make_dispute

      unknown = described_class.call(dispute: dispute, evidence: { 'nope' => 'x' })
      expect(unknown).not_to be_success
      expect(unknown.error.to_s).to include('unknown_evidence_key')

      empty = described_class.call(dispute: dispute, evidence: {})
      expect(empty).not_to be_success
      expect(empty.error.to_s).to include('evidence_empty')
    end
  end

  describe 'AC-P78-10 逾期策略' do
    it 'requires explicit confirmation after the evidence deadline' do
      stub_catalog
      stub_write
      dispute = make_dispute(evidence_due_at: 2.hours.ago)

      blocked = described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane' })
      expect(blocked).not_to be_success
      expect(blocked.error.to_s).to include('late_submission_not_confirmed')

      confirmed = described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane' }, accept_late: true)
      expect(confirmed).to be_success
      expect(confirmed.value[:late]).to be(true)
      expect(confirmed.value[:submission].late).to be(true)
    end
  end

  describe 'AC-P78-09 provider 不支持 / 终态' do
    it 'degrades for gateways without a catalog' do
      dispute = make_dispute
      outcome = described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane' })
      expect(outcome).not_to be_success
      expect(outcome.error.to_s).to include('evidence_submission_unsupported')
    end

    it 'refuses terminal disputes' do
      stub_catalog
      stub_write
      dispute = make_dispute(state: 'won')
      outcome = described_class.call(dispute: dispute, evidence: { 'customer_name' => 'Jane' })
      expect(outcome).not_to be_success
      expect(outcome.error.to_s).to include('dispute_terminal')
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)
    end
  end

  describe 'AC-P78-02 文件证据' do
    it 'accepts file evidence and keeps it as an immutable receipt attachment' do
      stub_catalog
      stub_write
      dispute = make_dispute

      outcome = described_class.call(dispute: dispute, evidence: { 'receipt' => temp_evidence_file })

      expect(outcome).to be_success
      expect(outcome.value[:submission].evidence_files.count).to eq(1)
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(1)
    end

    it 'rejects files whose content type is not allow-listed' do
      stub_catalog
      dispute = make_dispute
      bad_file = double('EvidenceFile', read: 'MZ', path: '/tmp/evidence.exe', size: 2,
                                       content_type: 'application/x-msdownload')

      outcome = described_class.call(dispute: dispute, evidence: { 'receipt' => bad_file })

      expect(outcome).not_to be_success
      expect(outcome.error.to_s).to include('evidence_file_type_not_allowed')
    end
  end
end
