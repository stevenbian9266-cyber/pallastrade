# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-1 AC-R61-05/13/14/20 —— Refund durable lifecycle（状态机/scope/时间戳/终态）
RSpec.describe PallasTrade::Refund, type: :model do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  def requested_refund(amount: 20)
    create(:refund, payment: payment, amount: amount, transaction_id: nil, state: 'requested')
  end

  describe 'state default & constants' do
    it 'defaults to requested' do
      expect(described_class.new.state).to eq('requested')
    end

    it 'freezes lifecycle constants' do
      expect(described_class::STATES).to include('requested', 'processing', 'succeeded', 'failed', 'ambiguous', 'manual_review', 'canceled')
      expect(described_class::ACTIVE_STATES).to contain_exactly('requested', 'processing', 'ambiguous')
      expect(described_class::CAPACITY_STATES).to include('succeeded', 'requested', 'processing', 'ambiguous')
      expect(described_class::TERMINAL_STATES).to contain_exactly('succeeded', 'failed', 'manual_review', 'canceled')
    end
  end

  describe 'scopes' do
    it 'succeeds / failed / active / capacity_consuming' do
      ok = create(:refund, payment: payment, amount: 10, transaction_id: 're_1') # factory default succeeded
      bad = create(:refund, payment: payment, amount: 10, transaction_id: nil, state: 'failed')
      inflight = create(:refund, payment: payment, amount: 10, transaction_id: nil, state: 'ambiguous')

      expect(described_class.succeeded).to include(ok)
      expect(described_class.failed).to include(bad)
      expect(described_class.active).to include(inflight)
      expect(described_class.capacity_consuming).to include(ok, inflight)
      expect(described_class.capacity_consuming).not_to include(bad)
    end
  end

  describe 'state machine' do
    it 'requested → processing → succeeded with timestamps + transaction_id (apply_success!)' do
      refund = requested_refund
      expect { refund.start_processing! }.to change(refund, :state).from('requested').to('processing')
      expect(refund.processing_at).to be_present

      expect(refund.apply_success!(authorization: 're_provider_1', response: double(params: {}))).to be(true)
      expect(refund).to be_succeeded
      expect(refund.transaction_id).to eq('re_provider_1')
      expect(refund.succeeded_at).to be_present
    end

    it 'requested → failed persists record with error and does not raise (record_failure!)' do
      refund = requested_refund
      expect { refund.record_failure!(code: 'PROVIDER_REJECTED', message: 'card declined') }.not_to raise_error
      expect(refund).to be_failed
      expect(refund.last_error_code).to eq('PROVIDER_REJECTED')
      expect(refund.last_error_message).to eq('card declined')
      expect(refund.failed_at).to be_present
      expect(PallasTrade::Refund.exists?(refund.id)).to be(true)
    end

    it 'processing → ambiguous on unknown outcome; no auto retry; can go manual_review' do
      refund = requested_refund
      refund.start_processing!
      expect { refund.record_ambiguous!(code: 'PROVIDER_AMBIGUOUS', message: 'timeout') }.not_to raise_error
      expect(refund).to be_ambiguous
      expect(refund.ambiguous_at).to be_present
      expect(refund.last_error_message).to eq('timeout')

      expect { refund.enter_manual_review!(message: 'manual check') }.not_to raise_error
      expect(refund).to be_manual_review
    end

    it 'rejects illegal transitions (terminal → processing)' do
      ok = create(:refund, payment: payment, amount: 10, transaction_id: 're_x')
      expect(ok).to be_succeeded
      expect(ok.can_start_processing?).to be(false)
      expect { ok.start_processing! }.to raise_error(StateMachines::InvalidTransition)
    end

    it 'cancel_request only allowed from requested' do
      refund = requested_refund
      expect { refund.cancel_request! }.to change(refund, :state).from('requested').to('canceled')
      failed = create(:refund, payment: payment, amount: 10, transaction_id: nil, state: 'failed')
      expect(failed.can_cancel_request?).to be(false)
    end
  end

  describe 'ownership & idempotency' do
    it 'execution_idempotency_key is stable and prefixed after persist' do
      refund = requested_refund
      expect(refund.execution_idempotency_key).to eq("refund:#{refund.prefixed_id}:execute")
    end
  end
end
