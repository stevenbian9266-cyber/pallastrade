# frozen_string_literal: true

# PRD-20260913-payments-dsp-p7-8-dispute-dangerous-actions-and-evidence-submission
# AC-P78-06/07/09/11/12/13 —— 接受争议（不可逆）：必填理由、能力探测、审计、事件、
# 不改本地状态机、零资金副作用、幂等。
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe PallasTrade::Disputes::AcceptDispute do
  let!(:store) { create(:store, code: "p78_accept_#{SecureRandom.hex(4)}", default: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def make_dispute(state: 'needs_response')
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p78a@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p78a_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_p78a_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd',
      store_id: store.id, payment: payment, order: order
    )
  end

  def stub_accept(status: 'lost', reference: 'dp_closed', raise_error: nil)
    if raise_error
      allow_any_instance_of(payment_method.class).to receive(:accept_dispute).and_raise(raise_error)
    else
      allow_any_instance_of(payment_method.class).to receive(:accept_dispute).and_return(
        { provider_reference: reference, status: status, metadata: {} }
      )
    end
  end

  def money_counts
    {
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      orders: PallasTrade::Order.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count
    }
  end

  describe 'AC-P78-06 接受成功' do
    it 'accepts through the provider, records a receipt, audits and never touches local state or money' do
      stub_accept(status: 'lost')
      dispute = make_dispute
      before_counts = money_counts

      expect(PallasTrade::Events).to receive(:publish).with(
        'dispute.accepted', hash_including(dispute_id: dispute.prefixed_id), anything
      ).and_call_original

      outcome = described_class.call(dispute: dispute, reason: 'delivery proof unavailable',
                                     actor: { type: 'PallasTrade::AdminUser', id: 9, label: 'lead@example.com' })

      expect(outcome).to be_success
      submission = outcome.value[:submission]
      expect(submission.kind).to eq('accepted')
      expect(submission.accepted_reason).to eq('delivery proof unavailable')
      expect(submission.provider_status).to eq('lost')
      expect(submission.provider_reference).to eq('dp_closed')

      expect(PallasTrade::AuditLog.where(action: 'dispute_accepted').count).to eq(1)

      # 本地状态机**不变**（由 webhook / 收敛推进）
      expect(dispute.reload.state).to eq('needs_response')

      # AC-P78-12：零资金副作用
      expect(money_counts).to eq(before_counts)
    end
  end

  describe 'AC-P78-07 理由必填' do
    it 'rejects a blank reason without calling the provider' do
      stub_accept
      dispute = make_dispute

      outcome = described_class.call(dispute: dispute, reason: '   ')

      expect(outcome).not_to be_success
      expect(outcome.error.to_s).to include('reason_required')
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)
    end
  end

  describe 'AC-P78-04 幂等' do
    it 'returns the existing receipt for the same reason' do
      stub_accept
      dispute = make_dispute

      first = described_class.call(dispute: dispute, reason: 'no proof')
      second = described_class.call(dispute: dispute, reason: 'no proof')

      expect(first).to be_success
      expect(second.value[:idempotent]).to be(true)
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(1)
    end
  end

  describe 'AC-P78-09 能力与终态' do
    it 'degrades when the gateway has no accept contract' do
      dispute = make_dispute
      outcome = described_class.call(dispute: dispute, reason: 'no proof')
      expect(outcome).not_to be_success
      expect(outcome.error.to_s).to include('accept_unsupported')
    end

    it 'refuses to accept an already-terminal dispute' do
      stub_accept
      dispute = make_dispute(state: 'won')
      outcome = described_class.call(dispute: dispute, reason: 'no proof')
      expect(outcome).not_to be_success
      expect(outcome.error.to_s).to include('dispute_terminal')
    end
  end

  describe 'AC-P78-05 provider 失败' do
    it 'returns failure, writes no receipt and audits the attempt' do
      stub_accept(raise_error: PallasTrade::Core::GatewayError.new('nope'))
      dispute = make_dispute

      outcome = described_class.call(dispute: dispute, reason: 'no proof')

      expect(outcome).not_to be_success
      expect(outcome.error.to_s).to include('provider_error')
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)
      expect(PallasTrade::AuditLog.where(action: 'dispute_accept_failed').count).to eq(1)
    end
  end
end
