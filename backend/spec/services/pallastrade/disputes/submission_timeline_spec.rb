# frozen_string_literal: true

# PRD-20260913-payments (DSP-P7-10 B1) AC-004 / AC-010
# —— 证据版本与回执追踪：时间线、版本号、相对上一版的证据键 diff；只读（不新增/不改写回执）。
require 'rails_helper'

RSpec.describe PallasTrade::Disputes::SubmissionTimeline do
  let!(:store) { create(:store, code: "p710_timeline_#{SecureRandom.hex(4)}", default: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def make_dispute
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p710tl@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p710tl_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_p710tl_#{SecureRandom.hex(4)}",
      state: 'needs_response', amount: 12.34, currency: 'usd',
      store_id: store.id, payment: payment, order: order
    )
  end

  def receipt(dispute, kind:, keys:, digest:, status:, at:, reference: nil, late: false)
    PallasTrade::DisputeEvidenceSubmission.create!(
      dispute: dispute, kind: kind, payload_digest: digest,
      provider_status: status, provider_reference: reference,
      late: late, actor_type: 'PallasTrade::AdminUser', actor_id: '7', actor_label: 'ops@example.com',
      response_metadata: { 'evidence_keys' => keys }, created_at: at, updated_at: at
    )
  end

  describe 'AC-004 时间线与版本' do
    it 'lists submissions newest-first with per-kind versions and key diffs' do
      dispute = make_dispute
      v1_time = 3.days.ago
      v2_time = 2.days.ago
      receipt(dispute, kind: 'evidence_submitted', keys: %w[customer_name receipt], digest: 'a' * 64,
                      status: 'under_review', reference: 'dp_v1', at: v1_time)
      receipt(dispute, kind: 'evidence_submitted', keys: %w[customer_name product_description], digest: 'b' * 64,
                      status: 'under_review', reference: 'dp_v2', at: v2_time, late: true)

      outcome = described_class.call(dispute: dispute)

      expect(outcome).to be_success
      timeline = outcome.value
      expect(timeline[:count]).to eq(2)
      expect(timeline[:versions]).to eq('evidence_submitted' => 2)

      newest = timeline[:entries].first
      expect(newest[:version]).to eq(2)
      expect(newest[:provider_status]).to eq('under_review')
      expect(newest[:provider_reference]).to eq('dp_v2')
      expect(newest[:actor][:label]).to eq('ops@example.com')
      expect(newest[:late]).to be(true)
      expect(newest[:diff][:added]).to eq(['product_description'])
      expect(newest[:diff][:removed]).to eq(['receipt'])
      expect(newest[:diff][:kept]).to eq(['customer_name'])

      oldest = timeline[:entries].last
      expect(oldest[:version]).to eq(1)
      expect(oldest[:diff][:first]).to be(true)
      expect(oldest[:diff][:added]).to eq(%w[customer_name receipt])
      expect(oldest[:previous_id]).to be_nil

      # latest = 最新一条（时间线按时间递增取末位）
      expect(timeline[:latest][:version]).to eq(2)
      expect(timeline[:latest][:provider_reference]).to eq('dp_v2')
    end

    it 'keeps versions independent per kind and supports filtering' do
      dispute = make_dispute
      receipt(dispute, kind: 'evidence_submitted', keys: %w[customer_name], digest: 'c' * 64,
                      status: 'under_review', at: 3.days.ago)
      receipt(dispute, kind: 'accepted', keys: [], digest: 'd' * 64, status: 'lost', at: 1.day.ago)

      both = described_class.call(dispute: dispute).value
      expect(both[:versions]).to eq('evidence_submitted' => 1, 'accepted' => 1)
      expect(both[:kinds]).to contain_exactly('evidence_submitted', 'accepted')

      only_accepted = described_class.call(dispute: dispute, kind: 'accepted').value
      expect(only_accepted[:count]).to eq(1)
      expect(only_accepted[:entries].first[:kind]).to eq('accepted')
    end

    it 'returns an empty timeline for a dispute without submissions' do
      timeline = described_class.call(dispute: make_dispute).value

      expect(timeline[:count]).to eq(0)
      expect(timeline[:entries]).to be_empty
      expect(timeline[:latest]).to be_nil
    end

    it 'never writes or mutates receipts, and degrades on nil dispute' do
      dispute = make_dispute
      receipt(dispute, kind: 'evidence_submitted', keys: %w[customer_name], digest: 'e' * 64,
                      status: 'under_review', at: 1.day.ago)
      before_counts = { submissions: PallasTrade::DisputeEvidenceSubmission.count,
                        audits: PallasTrade::AuditLog.count,
                        payments: PallasTrade::Payment.count }
      before_updated_at = PallasTrade::DisputeEvidenceSubmission.first.updated_at

      described_class.call(dispute: dispute)
      described_class.call(dispute: nil)

      expect({ submissions: PallasTrade::DisputeEvidenceSubmission.count,
                audits: PallasTrade::AuditLog.count,
                payments: PallasTrade::Payment.count }).to eq(before_counts)
      expect(PallasTrade::DisputeEvidenceSubmission.first.updated_at).to eq(before_updated_at)
    end
  end
end
