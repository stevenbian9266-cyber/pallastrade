# frozen_string_literal: true

# PRD-20260913-payments (DSP-P7-10 B3 / FR-009) AC-009 / AC-010
# —— 回执单向状态机：submitted → acknowledged → rejected，由 provider 回写信号派生；
# 信号不足/冲突 → unknown（不猜）；**只读**（零写、零事件、零触网）。
require 'rails_helper'

RSpec.describe PallasTrade::Disputes::ReceiptStatus do
  let!(:store) { create(:store, code: "p710_rcpt_#{SecureRandom.hex(4)}", default: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def make_dispute(state: 'needs_response', attention_reason: nil, provider_status: nil)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p710rc@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p710rc_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p710rc_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd', attention_reason: attention_reason,
      private_metadata: provider_status ? { 'provider_status' => provider_status } : {},
      store_id: store.id, payment: payment, order: order
    )
  end

  def receipt(dispute, status:, digest:, at: 1.day.ago, late: false)
    PallasTrade::DisputeEvidenceSubmission.create!(
      dispute: dispute, kind: 'evidence_submitted', payload_digest: digest,
      provider_status: status, provider_reference: "dp_rc_#{digest[0, 6]}", late: late,
      response_metadata: { 'evidence_keys' => %w[customer_name] },
      created_at: at, updated_at: at
    )
  end

  def write_counts
    {
      submissions: PallasTrade::DisputeEvidenceSubmission.count,
      approvals: PallasTrade::DisputeEvidenceApproval.count,
      audits: PallasTrade::AuditLog.count,
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count
    }
  end

  describe 'AC-009 三态单向' do
    it 'reports submitted while no further provider signal exists' do
      dispute = make_dispute(state: 'needs_response')
      receipt(dispute, status: 'needs_response', digest: 'a' * 64)

      result = described_class.call(dispute: dispute).value

      expect(result[:state]).to eq('submitted')
      expect(result[:rank]).to eq(1)
      expect(result[:reasons]).to include('awaiting_provider_writeback')
      expect(result[:provider_status_at_submission]).to eq('needs_response')
    end

    it 'reports acknowledged once the provider moved the dispute into review' do
      dispute = make_dispute(state: 'under_review')
      receipt(dispute, status: 'under_review', digest: 'b' * 64)

      result = described_class.call(dispute: dispute).value

      expect(result[:state]).to eq('acknowledged')
      expect(result[:rank]).to eq(2)
      expect(result[:reasons]).to include('dispute_reached_under_review')
    end

    it 'reports acknowledged when the provider receipt itself came back under_review' do
      dispute = make_dispute(state: 'needs_response')
      receipt(dispute, status: 'under_review', digest: 'c' * 64)

      expect(described_class.call(dispute: dispute).value[:state]).to eq('acknowledged')
    end

    it 'reports rejected when the provider sent the dispute back for more evidence' do
      dispute = make_dispute(state: 'needs_response', attention_reason: 'invalid_transition',
                             provider_status: 'warning_needs_response')
      receipt(dispute, status: 'under_review', digest: 'd' * 64)

      result = described_class.call(dispute: dispute).value

      expect(result[:state]).to eq('rejected')
      expect(result[:rank]).to eq(3)
      expect(result[:reasons]).to include('provider_sent_dispute_back_for_evidence')
    end

    it 'never goes backwards: once rejected, a later call stays rejected (monotonic)' do
      dispute = make_dispute(state: 'needs_response', attention_reason: 'invalid_transition',
                             provider_status: 'needs_response')
      receipt(dispute, status: 'under_review', digest: 'e' * 64)

      first = described_class.call(dispute: dispute).value[:state]
      second = described_class.call(dispute: dispute.reload).value[:state]

      expect(first).to eq('rejected')
      expect(second).to eq('rejected')
    end
  end

  describe 'AC-009 不猜（unknown / 无回执）' do
    it 'returns a none-envelope when the dispute has no receipt at all' do
      dispute = make_dispute

      result = described_class.call(dispute: dispute).value

      expect(result[:state]).to be_nil
      expect(result[:reasons]).to include('no_receipt')
    end

    it 'returns unknown instead of guessing when the rejection signal conflicts with the state' do
      dispute = make_dispute(state: 'under_review', attention_reason: 'invalid_transition',
                             provider_status: 'under_review')
      receipt(dispute, status: 'under_review', digest: 'f' * 64)

      result = described_class.call(dispute: dispute).value

      expect(result[:state]).to eq('unknown')
      expect(result[:reasons]).to include('conflicting_signals')
    end

    it 'ignores an invalid_transition flag that is not a provider rejection' do
      dispute = make_dispute(state: 'needs_response', attention_reason: 'invalid_transition',
                             provider_status: nil)
      receipt(dispute, status: 'needs_response', digest: 'g' * 64)

      expect(described_class.call(dispute: dispute).value[:state]).to eq('submitted')
    end

    it 'still derives a state when the dispute has no payment anchor' do
      dispute = PallasTrade::Dispute.create!(
        provider: 'stripe', provider_dispute_reference: "dp_p710rc_#{SecureRandom.hex(4)}",
        state: 'under_review', amount: 5.0, currency: 'usd', store_id: store.id
      )
      receipt(dispute, status: 'under_review', digest: 'h' * 64)

      expect(described_class.call(dispute: dispute).value[:state]).to eq('acknowledged')
    end
  end

  describe 'AC-010 铁律：派生状态机零写' do
    it 'writes nothing and never mutates the immutable receipt' do
      dispute = make_dispute(state: 'under_review')
      record = receipt(dispute, status: 'under_review', digest: 'i' * 64)
      before = write_counts
      before_updated_at = record.updated_at

      3.times { described_class.call(dispute: dispute) }

      expect(write_counts).to eq(before)
      expect(PallasTrade::DisputeEvidenceSubmission.find(record.id).updated_at).to eq(before_updated_at)
      expect(dispute.reload.state).to eq('under_review')
    end
  end
end
