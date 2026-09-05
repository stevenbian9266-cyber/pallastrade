# frozen_string_literal: true

# TXN-P2-7 slice2 (REQ-20260905-txn-p2-7-admin-sweeper) AC-721/722/723
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe PallasTrade::Transactions::RecoverSweeperJob, type: :job do
  let(:store) { @default_store }

  def make_transaction(state:)
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: store.default_currency.to_s, amount: 100
    )
    case state
    when 'payment_pending'
      tx.start_payment!
    when 'payment_confirmed'
      tx.start_payment!
      tx.confirm_payment!
    when 'finalizing'
      tx.start_payment!
      tx.confirm_payment!
      tx.begin_finalizing!
    when 'recovery_required'
      tx.start_payment!
      tx.confirm_payment!
      tx.mark_recovery_required!
    when 'manual_review'
      tx.start_payment!
      tx.confirm_payment!
      tx.mark_recovery_required!
      tx.manual_review!
    end
    tx
  end

  def make_stuck(state)
    tx = make_transaction(state: state)
    tx.update_column(:updated_at, 2.hours.ago)
    tx
  end

  describe '#perform' do
    it 'AC-721 enqueues RecoverJob for recovery_required transactions' do
      tx = make_transaction(state: 'recovery_required')

      expect { described_class.perform_now }.
        to have_enqueued_job(PallasTrade::Transactions::RecoverJob).with(tx.prefixed_id)
    end

    it 'AC-722 leaves manual_review and stuck payment_confirmed/finalizing for humans (no enqueue)' do
      make_transaction(state: 'manual_review')
      make_stuck('payment_confirmed')
      make_stuck('finalizing')

      expect { described_class.perform_now }.
        not_to have_enqueued_job(PallasTrade::Transactions::RecoverJob)
    end

    it 'AC-722 fresh stuck-eligible states are not auto-recovered either (threshold)' do
      make_transaction(state: 'finalizing') # fresh — below threshold

      expect { described_class.perform_now }.
        not_to have_enqueued_job(PallasTrade::Transactions::RecoverJob)
    end

    it 'AC-723 runs repeatedly without errors when nothing actionable' do
      expect { described_class.perform_now }.not_to raise_error
      expect { described_class.perform_now }.not_to raise_error
    end

    it 'logs a warn alert when human-attention transactions exist (metrics/alerts)' do
      make_transaction(state: 'manual_review')
      warns = []
      allow(Rails.logger).to receive(:warn) { |message| warns << message.to_s; true }

      described_class.perform_now

      expect(warns).to include(a_string_matching(/human attention/))
    end
  end
end
