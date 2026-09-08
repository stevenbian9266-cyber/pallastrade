# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-8d AC-R68D-01~04 —— Refunds::OrphanPairing 只读孤儿退款配对
RSpec.describe PallasTrade::Refunds::OrphanPairing, type: :service do
  let(:store) { create(:store, code: "orphan_store_#{SecureRandom.hex(4)}") }
  let(:reason) { create(:refund_reason) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def completed_payment(session: false)
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 100.0)
    if session
      txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100)
      s = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                         amount: 100, currency: 'USD', commerce_transaction: txn)
      payment.update_column(:payment_session_id, s.id)
    end
    payment
  end

  def succeeded_refund(payment:, transaction_id: nil)
    create(:refund, payment: payment, reason: reason, amount: 10, state: 'succeeded',
                    transaction_id: transaction_id || "re_bogus_#{rand(1_000_000)}",
                    succeeded_at: Time.current, provider_idempotency_key: "refund:re_#{SecureRandom.hex(4)}:execute")
  end

  describe 'AC-R68D-01 matched（Bogus 真跑）' do
    it 'provider ids（Bogus 派生 re_bogus_<id>）与本地 succeeded 引用全部匹配 → matched' do
      payment = completed_payment(session: true)
      refund = succeeded_refund(payment: payment, transaction_id: nil)
      refund.update_columns(transaction_id: "re_bogus_#{refund.id}")

      outcome = described_class.call(payment: payment)
      expect(outcome).to be_success
      result = outcome.value
      expect(result.status).to eq('matched')
      expect(result.matched).to include(a_hash_including(provider_id: "re_bogus_#{refund.id}"))
      expect(result.orphans).to be_empty
      expect(result.local_unmatched).to be_empty
    end
  end

  describe 'AC-R68D-02 orphan（provider-only）' do
    it 'provider 含本地无记录 id → orphans + needs_attention(ORPHAN_REFUND)' do
      payment = completed_payment(session: true)
      allow(payment.payment_method).to receive(:fetch_financial_details)
        .and_return(provider_refund_references: ['re_orphan_1', 're_orphan_2'])

      outcome = described_class.call(payment: payment)
      expect(outcome).to be_success
      result = outcome.value
      expect(result.status).to eq('needs_attention')
      expect(result.reasons).to include('ORPHAN_REFUND')
      expect(result.orphans.map { |o| o[:provider_id] }).to contain_exactly('re_orphan_1', 're_orphan_2')
    end
  end

  describe 'AC-R68D-03 local_unmatched' do
    it '本地 succeeded 引用不在 provider → local_unmatched + needs_attention(LOCAL_REFUND_NOT_ON_PROVIDER)' do
      payment = completed_payment(session: true)
      succeeded_refund(payment: payment, transaction_id: 're_local_only')

      outcome = described_class.call(payment: payment)
      expect(outcome).to be_success
      result = outcome.value
      expect(result.status).to eq('needs_attention')
      expect(result.reasons).to include('LOCAL_REFUND_NOT_ON_PROVIDER')
      expect(result.local_unmatched.map { |u| u[:transaction_id] }).to include('re_local_only')
    end
  end

  describe 'AC-R68D-04 能力/锚点/异常' do
    it 'StoreCredit/Check → not_applicable（不调 provider）' do
      check = create(:check_payment)
      outcome = described_class.call(payment: check)
      expect(outcome).to be_success
      expect(outcome.value.status).to eq('not_applicable')
    end

    it '无 fetch_financial_details 实现 → unsupported' do
      payment = completed_payment(session: true)
      allow(PallasTrade::FinancialFacts::CaptureEvidencePolicy).to receive(:implements_financial_details?)
        .and_return(false)

      outcome = described_class.call(payment: payment)
      expect(outcome).to be_success
      expect(outcome.value.status).to eq('unsupported')
    end

    it '无 provider session 锚点 → unavailable(UNLINKED_LEGACY_PAYMENT)，不 raise' do
      payment = completed_payment(session: false)
      outcome = described_class.call(payment: payment)
      expect(outcome).to be_success
      expect(outcome.value.status).to eq('unavailable')
      expect(outcome.value.reasons).to include('UNLINKED_LEGACY_PAYMENT')
    end

    it 'provider 异常 → unavailable(PROVIDER_UNAVAILABLE)，不 raise' do
      payment = completed_payment(session: true)
      allow(payment.payment_method).to receive(:fetch_financial_details)
        .and_raise(PallasTrade::Core::GatewayError, 'provider down')

      outcome = described_class.call(payment: payment)
      expect(outcome).to be_success
      expect(outcome.value.status).to eq('unavailable')
      expect(outcome.value.reasons.first).to eq('PROVIDER_UNAVAILABLE')
    end
  end
end
