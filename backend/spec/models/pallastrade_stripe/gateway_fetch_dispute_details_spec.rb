# frozen_string_literal: true

require 'rails_helper'
require 'stripe'

# PRD-20260911-payments-dsp-p7-2-dispute-fact-resolution AC-001
# Stripe 网关的 dispute 只读契约：`fetch_dispute_details` 归一 + capability 语义（只读、零 provider mutation）。
RSpec.describe PallasTradeStripe::Gateway, type: :model do
  subject(:gateway) { create(:stripe_gateway) }

  let(:dispute) do
    PallasTrade::Dispute.new(provider: 'stripe', provider_dispute_reference: 'dp_fetch_1',
                             state: 'needs_response', amount: 25, currency: 'usd')
  end

  def stripe_dispute(**overrides)
    Stripe::Dispute.construct_from(
      { id: 'dp_fetch_1', status: 'needs_response', amount: 2500, currency: 'usd',
        reason: 'fraudulent', network_reason_code: '10.4',
        evidence_details: { due_by: Time.zone.parse('2026-09-20 12:00:00').to_i, has_evidence: false },
        balance_transactions: [{ id: 'txn_dispute_debit' }, { id: 'txn_dispute_fee' }] }.merge(overrides)
    )
  end

  describe '#fetch_dispute_details（AC-001）' do
    it 'returns a normalized provider snapshot (amount in major units)' do
      allow(gateway).to receive(:retrieve_dispute).with('dp_fetch_1').and_return(stripe_dispute)

      details = gateway.fetch_dispute_details(dispute: dispute)

      expect(details[:provider_dispute_reference]).to eq('dp_fetch_1')
      expect(details[:status]).to eq('needs_response')
      expect(details[:amount]).to eq(BigDecimal('25'))
      expect(details[:currency]).to eq('usd')
      expect(details[:reason]).to eq('fraudulent')
      expect(details[:network_reason_code]).to eq('10.4')
      expect(details[:evidence_due_at]).to be_within(1.second).of(Time.zone.parse('2026-09-20 12:00:00'))
      expect(details[:has_evidence]).to be(false)
      expect(details[:balance_transaction_references]).to eq(%w[txn_dispute_debit txn_dispute_fee])
      expect(details[:observed_at]).to be_present
    end

    it 'does not divide zero-decimal currencies' do
      allow(gateway).to receive(:retrieve_dispute).and_return(stripe_dispute(amount: 2500, currency: 'jpy'))

      expect(gateway.fetch_dispute_details(dispute: dispute)[:amount]).to eq(BigDecimal('2500'))
    end

    it 'degrades missing provider fields to nil (no guessing)' do
      allow(gateway).to receive(:retrieve_dispute).and_return(
        Stripe::Dispute.construct_from(id: 'dp_fetch_1', status: 'needs_response')
      )

      details = gateway.fetch_dispute_details(dispute: dispute)

      expect(details[:amount]).to be_nil
      expect(details[:evidence_due_at]).to be_nil
      expect(details[:balance_transaction_references]).to eq([])
    end

    it 'raises GatewayError when the dispute has no provider reference' do
      allow(gateway).to receive(:retrieve_dispute)
      orphan = PallasTrade::Dispute.new(provider: 'stripe', state: 'opened', amount: 1, currency: 'usd')

      expect { gateway.fetch_dispute_details(dispute: orphan) }.to raise_error(PallasTrade::Core::GatewayError, /no provider dispute reference/)
      expect(gateway).not_to have_received(:retrieve_dispute)
    end

    it 'is read-only (no local writes / no provider mutation besides retrieve)' do
      persisted = PallasTrade::Dispute.create!(provider: 'stripe', provider_dispute_reference: 'dp_ro_1',
                                               state: 'needs_response', amount: 25, currency: 'usd')
      allow(gateway).to receive(:retrieve_dispute).and_return(stripe_dispute)

      gateway.fetch_dispute_details(dispute: persisted)

      expect(gateway).to have_received(:retrieve_dispute).once
      expect(persisted.changed?).to be(false)
      expect(persisted.reload.state).to eq('needs_response')
    end
  end

  describe '契约 capability（AC-001）' do
    it 'base PaymentMethod raises NotImplementedError' do
      expect { PallasTrade::PaymentMethod.new.fetch_dispute_details(dispute: dispute) }.to raise_error(NotImplementedError, /fetch_dispute_details/)
    end

    it 'stripe gateway implements the contract (method owner != base)' do
      expect(gateway.respond_to?(:fetch_dispute_details)).to be(true)
      expect(gateway.method(:fetch_dispute_details).owner).not_to eq(PallasTrade::PaymentMethod)
      expect(PallasTrade::PaymentMethod.new.method(:fetch_dispute_details).owner).to eq(PallasTrade::PaymentMethod)
    end
  end
end
