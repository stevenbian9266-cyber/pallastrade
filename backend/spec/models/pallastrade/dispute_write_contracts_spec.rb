# frozen_string_literal: true

# PRD-20260913-payments-dsp-p7-8-dispute-dangerous-actions-and-evidence-submission
# AC-P78-01/02 —— 写契约与目录契约（基类拒答 / 适配器实现 / Stripe 真实目录）、
# 回执模型不可变性（AC-P78-03 的存储侧保障）。
require 'rails_helper'

RSpec.describe 'Dispute write contracts and immutable receipts' do
  describe 'AC-P78-01 provider 写契约' do
    it 'raises on the base PaymentMethod (capability = subclass owner)' do
      base = PallasTrade::PaymentMethod
      expect { base.new.submit_dispute_evidence(dispute: nil, evidence: {}) }.to raise_error(NotImplementedError)
      expect { base.new.accept_dispute(dispute: nil, reason: 'x') }.to raise_error(NotImplementedError)
      expect(base.new.dispute_evidence_catalog).to eq([])
    end

    it 'is implemented by the Stripe gateway' do
      gateway = PallasTradeStripe::Gateway
      expect(gateway.instance_method(:submit_dispute_evidence).owner).to eq(gateway)
      expect(gateway.instance_method(:accept_dispute).owner).to eq(gateway)

      catalog = gateway.new.dispute_evidence_catalog
      expect(catalog.size).to be > 0
      expect(catalog.map { |entry| entry[:type] }.uniq).to match_array(%w[text file])
      expect(catalog.map { |entry| entry[:key] }).to include('customer_name', 'receipt')
    end
  end

  describe 'AC-P78-03 不可变回执' do
    let!(:store) { create(:store, code: "p78_receipt_#{SecureRandom.hex(4)}", default: true) }
    let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

    def dispute
      @dispute ||= begin
        order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                               item_total: 100, total: 100, payment_state: 'paid',
                               currency: store.default_currency, email: 'receipt@example.com')
        payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                                   state: 'completed', response_code: "pi_receipt_#{SecureRandom.hex(4)}",
                                   source: nil, skip_source_requirement: true)
        PallasTrade::Dispute.create!(provider: 'stripe', provider_dispute_reference: "dp_receipt_#{SecureRandom.hex(4)}",
                                     state: 'needs_response', amount: 12.34, currency: 'usd',
                                     store_id: store.id, payment: payment, order: order)
      end
    end

    def build_receipt(kind: 'evidence_submitted', digest: 'digest-1')
      PallasTrade::DisputeEvidenceSubmission.create!(
        dispute: dispute, kind: kind, payload_digest: digest,
        provider_reference: 'dp_1', provider_status: 'under_review',
        actor_type: 'PallasTrade::AdminUser', actor_id: '1', actor_label: 'ops@example.com'
      )
    end

    it 'is append-only: updates and update_columns are rejected' do
      receipt = build_receipt
      expect { receipt.update!(provider_status: 'other') }
        .to raise_error(PallasTrade::DisputeEvidenceSubmission::ImmutableError)
      expect { receipt.update_columns(provider_status: 'other') }
        .to raise_error(PallasTrade::DisputeEvidenceSubmission::ImmutableError)
      expect { receipt.destroy }
        .to raise_error(PallasTrade::DisputeEvidenceSubmission::ImmutableError)
    end

    it 'enforces idempotency uniqueness on (dispute, kind, payload_digest)' do
      build_receipt
      expect { build_receipt }.to raise_error(ActiveRecord::RecordInvalid)

      # 同 dispute 不同 kind 或不同 payload → 允许（append-only 追加）
      expect { build_receipt(kind: 'accepted', digest: 'digest-1') }.not_to raise_error
      expect { build_receipt(digest: 'digest-2') }.not_to raise_error
    end

    it 'builds a stable digest for the same payload regardless of key order' do
      first = PallasTrade::DisputeEvidenceSubmission.digest_for('customer_name' => 'Jane', 'files' => %w[a b])
      second = PallasTrade::DisputeEvidenceSubmission.digest_for('files' => %w[a b], 'customer_name' => 'Jane')
      expect(first).to eq(second)
    end
  end
end
