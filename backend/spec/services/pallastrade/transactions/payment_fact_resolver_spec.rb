# frozen_string_literal: true

# PRD-20260904-payments-txn-p2-3 AC-301..308/310
require 'rails_helper'

RSpec.describe PallasTrade::Transactions::PaymentFactResolver, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 10, total: 10, payment_state: 'balance_due')
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:currency) { store.default_currency.to_s }

  def make_transaction(amount: 10)
    PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: currency, amount: amount
    )
  end

  def make_session(transaction, status: 'pending', amount: 10)
    create(:bogus_payment_session, order: order, payment_method: payment_method, status: status,
                                   amount: amount, currency: currency, commerce_transaction: transaction)
  end

  def settle!(session, amount: 10)
    create(:payment, order: order, payment_method: payment_method,
                     amount: amount, state: 'completed', payment_session: session)
  end

  def provider_result(status)
    { status: status, amount_cents: 1000, currency: 'usd', provider_reference: 'pi_test' }
  end

  def resolve(transaction, **opts)
    described_class.call(transaction: transaction, **opts)
  end

  describe '#call' do
    it 'AC-301 local completed Payment (amount matched) → paid, without provider query' do
      tx = make_transaction
      make_session(tx, status: 'completed')
      tx.payment_sessions.each { |s| settle!(s) }

      expect(payment_method).not_to receive(:fetch_payment_status)

      result = resolve(tx)
      expect(result).to be_success
      expect(result.value[:verdict]).to eq(:paid)
      expect(result.value[:reasons]).to include(:payment_completed)
    end

    it 'AC-302 session completed without Payment + provider succeeded → paid' do
      tx = make_transaction
      make_session(tx, status: 'completed') # Payment 缺失（webhook 丢失等不一致场景）
      # bogus 确定性契约：completed → provider :paid

      result = resolve(tx)
      expect(result).to be_success
      expect(result.value[:verdict]).to eq(:paid)
      expect(result.value[:reasons]).to include(:provider_confirmed)
      expect(result.value[:provider_results]).not_to be_empty
    end

    it 'AC-303 all attempts terminal-failed → unpaid' do
      tx = make_transaction
      make_session(tx, status: 'failed')
      make_session(tx, status: 'canceled')
      make_session(tx, status: 'expired')

      expect(payment_method).not_to receive(:fetch_payment_status)

      result = resolve(tx)
      expect(result.value[:verdict]).to eq(:unpaid)
      expect(result.value[:reasons]).to eq([:all_failed])
    end

    it 'AC-304 no payment sessions → unpaid (no_attempt)' do
      tx = make_transaction

      result = resolve(tx)
      expect(result.value[:verdict]).to eq(:unpaid)
      expect(result.value[:reasons]).to eq([:no_attempt])
    end

    it 'AC-305 pending attempt + provider processing → ambiguous' do
      tx = make_transaction
      make_session(tx, status: 'pending')
      # bogus 确定性契约：pending → provider :processing

      result = resolve(tx)
      expect(result.value[:verdict]).to eq(:ambiguous)
      expect(result.value[:reasons]).to include(:provider_pending)
    end

    it 'AC-306 provider network failure → ambiguous (provider_unavailable)' do
      tx = make_transaction
      make_session(tx, status: 'pending')
      allow_any_instance_of(PallasTrade::Gateway::Bogus).
        to receive(:fetch_payment_status).and_raise(StandardError, 'timeout')

      result = resolve(tx)
      expect(result.value[:verdict]).to eq(:ambiguous)
      expect(result.value[:reasons]).to include(:provider_unavailable)
    end

    it 'AC-306b provider_query: false with pending attempt → ambiguous, no outbound call' do
      tx = make_transaction
      make_session(tx, status: 'pending')

      expect(payment_method).not_to receive(:fetch_payment_status)

      result = resolve(tx, provider_query: false)
      expect(result.value[:verdict]).to eq(:ambiguous)
      expect(result.value[:reasons]).to include(:provider_skipped)
    end

    it 'AC-307 provider returns canceled → unpaid' do
      tx = make_transaction
      make_session(tx, status: 'pending') # 本地仍 pending，provider 权威已取消
      allow_any_instance_of(PallasTrade::Gateway::Bogus).
        to receive(:fetch_payment_status).and_return(provider_result(:canceled))

      result = resolve(tx)
      expect(result.value[:verdict]).to eq(:unpaid)
      expect(result.value[:reasons]).to include(:provider_unpaid)
    end

    it 'AC-308 bogus fetch_payment_status returns a normalized read-only hash' do
      tx = make_transaction
      completed = make_session(tx, status: 'completed')
      pending = make_session(tx, status: 'pending')
      canceled = make_session(tx, status: 'canceled')

      paid = payment_method.fetch_payment_status(payment_session: completed)
      expect(paid[:status]).to eq(:paid)
      expect(paid[:amount_cents]).to eq(1000)
      expect(paid[:currency]).to eq(currency)
      expect(paid[:provider_reference]).to eq(completed.external_id)

      expect(payment_method.fetch_payment_status(payment_session: pending)[:status]).to eq(:processing)
      expect(payment_method.fetch_payment_status(payment_session: canceled)[:status]).to eq(:canceled)
    end

    it 'AC-310 partial payment (< transaction amount) → ambiguous (short_payment)' do
      tx = make_transaction(amount: 10)
      sess = make_session(tx, status: 'completed', amount: 5)
      settle!(sess, amount: 5)

      expect(payment_method).not_to receive(:fetch_payment_status)

      result = resolve(tx)
      expect(result.value[:verdict]).to eq(:ambiguous)
      expect(result.value[:reasons]).to include(:short_payment)
    end

    it 'returns failure for a nil transaction' do
      result = described_class.call(transaction: nil)
      expect(result).to be_failure
    end
  end
end
