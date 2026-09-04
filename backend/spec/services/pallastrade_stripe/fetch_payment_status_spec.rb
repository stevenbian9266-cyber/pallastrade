# frozen_string_literal: true

# PRD-20260904-payments-txn-p2-3 AC-309
require 'spec_helper'

# TXN-P2-3: Stripe read-only provider status contract — fetch_payment_status.
# Uses real factory-built Stripe gateway + stubbed network (retrieve), never
# hits Stripe and never mutates local state.
RSpec.describe 'Stripe Gateway fetch_payment_status (TXN-P2-3)', type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 100, total: 100, payment_state: 'balance_due')
  end
  let(:gateway) { create(:stripe_gateway, store: store, active: true) }

  def build_session(external_id:, mode: nil)
    external_data = mode ? { 'mode' => mode } : { 'client_secret' => 'cs_test_secret' }
    PallasTrade::PaymentSessions::Stripe.new(
      order: order,
      payment_method: gateway,
      amount: 100,
      currency: 'USD',
      status: 'pending',
      external_id: external_id,
      external_data: external_data
    ).tap(&:save!)
  end

  let(:fake_intent) do
    Struct.new(:id, :status, :amount, :currency).new('pi_test_456', 'succeeded', 10_000, 'usd')
  end

  def fake_checkout_session(payment_status:)
    Struct.new(:id, :payment_status, :payment_intent).new('cs_test_123', payment_status, fake_intent)
  end

  def stub_intent(status:)
    allow(gateway).to receive(:retrieve_payment_intent).and_return(
      Struct.new(:id, :status, :amount, :currency).new('pi_test_456', status, 10_000, 'usd')
    )
  end

  describe '#fetch_payment_status' do
    it 'AC-309 pi_ mode: succeeded → paid with provider reference' do
      session = build_session(external_id: 'pi_test_456', mode: 'payment_intent')
      stub_intent(status: 'succeeded')

      status = gateway.fetch_payment_status(payment_session: session)

      expect(status[:status]).to eq(:paid)
      expect(status[:amount_cents]).to eq(10_000)
      expect(status[:currency]).to eq('usd')
      expect(status[:provider_reference]).to eq('pi_test_456')
    end

    it 'AC-309 pi_ mode: canceled → canceled; processing → processing; requires_capture → requires_capture' do
      { 'canceled' => :canceled, 'processing' => :processing, 'requires_capture' => :requires_capture }.each_with_index do |(status, expected), index|
        session = build_session(external_id: "pi_test_#{index}", mode: 'payment_intent')
        stub_intent(status: status)

        expect(gateway.fetch_payment_status(payment_session: session)[:status]).to eq(expected)
      end
    end

    it 'AC-309 pi_ mode: requires_payment_method → unpaid; requires_action → requires_action' do
      { 'requires_payment_method' => :unpaid, 'requires_action' => :requires_action }.each_with_index do |(status, expected), index|
        session = build_session(external_id: "pi_test_#{index}", mode: 'payment_intent')
        stub_intent(status: status)

        expect(gateway.fetch_payment_status(payment_session: session)[:status]).to eq(expected)
      end
    end

    it 'AC-309 cs_ mode: paid → paid (provider reference = cs_ session id)' do
      session = build_session(external_id: 'cs_test_123')
      allow(gateway).to receive(:retrieve_checkout_session).and_return(fake_checkout_session(payment_status: 'paid'))

      status = gateway.fetch_payment_status(payment_session: session)

      expect(status[:status]).to eq(:paid)
      expect(status[:provider_reference]).to eq('cs_test_123')
    end

    it 'AC-309 cs_ mode: unpaid → unpaid; no_payment_required → paid' do
      { 'unpaid' => :unpaid, 'no_payment_required' => :paid }.each_with_index do |(payment_status, expected), index|
        session = build_session(external_id: "cs_test_#{index}")
        allow(gateway).to receive(:retrieve_checkout_session).
          and_return(fake_checkout_session(payment_status: payment_status))

        expect(gateway.fetch_payment_status(payment_session: session)[:status]).to eq(expected)
      end
    end

    it 'AC-309 raises GatewayError when the session has no PaymentIntent yet' do
      session = build_session(external_id: 'pi_test_456', mode: 'payment_intent')
      allow(gateway).to receive(:retrieve_payment_intent).and_return(nil)

      expect { gateway.fetch_payment_status(payment_session: session) }.
        to raise_error(PallasTrade::Core::GatewayError, /no PaymentIntent yet/i)
    end

    it 'AC-309 is read-only: never creates payments or transitions sessions' do
      session = build_session(external_id: 'pi_test_456', mode: 'payment_intent')
      stub_intent(status: 'succeeded')

      expect { gateway.fetch_payment_status(payment_session: session) }.
        not_to(change { PallasTrade::Payment.count })
      expect(session.reload.status).to eq('pending')
    end
  end
end
