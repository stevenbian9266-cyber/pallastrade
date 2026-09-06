# frozen_string_literal: true

require 'spec_helper'

# PRD-20260906-payments-fin-p4-5 AC-4P5-01/02/03/04/05/09
# Stripe fetch_financial_details —— 只读归一财务快照（PI/Charge/BalanceTransaction/Refunds）。
RSpec.describe PallasTradeStripe::Gateway, type: :model do
  subject(:gateway) { create(:stripe_gateway) }

  Charge   = Struct.new(:id, :amount, :currency, :balance_transaction)
  PI       = Struct.new(:id, :status, :latest_charge, :amount, :currency)
  BT       = Struct.new(:id, :fee, :net, :currency)
  Refund   = Struct.new(:id, :amount)
  RefundList = Struct.new(:data)

  def pi_session(external_id:, mode: true)
    described_class_session_class = PallasTrade::PaymentSessions::Stripe
    described_class_session_class.new(
      payment_method: gateway,
      amount: 100,
      currency: 'USD',
      status: 'pending',
      external_id: external_id,
      external_data: mode ? { 'mode' => 'payment_intent' } : {}
    )
  end

  def stub_intent(session, intent)
    if session.payment_intent_mode?
      allow(gateway).to receive(:retrieve_payment_intent).and_return(intent)
    else
      cs = Struct.new(:id, :payment_status, :payment_intent).new('cs_1', 'paid', intent)
      allow(gateway).to receive(:retrieve_checkout_session).and_return(cs)
    end
  end

  before do
    Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', 'sk_test_placeholder')
    allow(Stripe::Refund).to receive(:list).and_return(RefundList.new([]))
  end

  it 'AC-4P5-01 cs_ mode settled → full normalized snapshot (pi_/ch_/txn_ refs + gross + fee/net + refund_total)' do
    session = pi_session(external_id: 'cs_test_1', mode: false)
    intent = PI.new('pi_test_1', 'succeeded', 'ch_test_1', 10_000, 'usd')
    stub_intent(session, intent)
    charge = Charge.new('ch_test_1', 10_000, 'usd', 'txn_test_1')
    allow(gateway).to receive(:retrieve_charge).with('ch_test_1').and_return(charge)
    allow(gateway).to receive(:retrieve_balance_transaction).with('txn_test_1')
                                                          .and_return(BT.new('txn_test_1', 300, 9700, 'usd'))
    allow(Stripe::Refund).to receive(:list).and_return(RefundList.new([Refund.new('re_test_1', 500)]))

    details = gateway.fetch_financial_details(payment_session: session)

    expect(details[:provider_payment_reference]).to eq('pi_test_1')
    expect(details[:provider_charge_reference]).to eq('ch_test_1')
    expect(details[:provider_balance_transaction_reference]).to eq('txn_test_1')
    expect(details[:provider_refund_references]).to eq(%w[re_test_1])
    expect(details[:gross_amount]).to eq(100.0)
    expect(details[:gross_currency]).to eq('usd')
    expect(details[:fee_amount]).to eq(3.0)
    expect(details[:fee_currency]).to eq('usd')
    expect(details[:net_amount]).to eq(97.0)
    expect(details[:net_currency]).to eq('usd')
    expect(details[:refund_total]).to eq(5.0)
    expect(details[:settlement_status]).to eq('settled')
    expect(details[:observed_at]).to be_present
  end

  it 'AC-4P5-02 pi_ mode settled → same normalized snapshot without Checkout Session' do
    session = pi_session(external_id: 'pi_test_2', mode: true)
    intent = PI.new('pi_test_2', 'succeeded', 'ch_test_2', 20_000, 'usd')
    stub_intent(session, intent)
    charge = Charge.new('ch_test_2', 20_000, 'usd', 'txn_test_2')
    allow(gateway).to receive(:retrieve_charge).with('ch_test_2').and_return(charge)
    allow(gateway).to receive(:retrieve_balance_transaction).with('txn_test_2')
                                                          .and_return(BT.new('txn_test_2', 600, 19_400, 'usd'))

    details = gateway.fetch_financial_details(payment_session: session)
    expect(details[:settlement_status]).to eq('settled')
    expect(details[:gross_amount]).to eq(200.0)
    expect(details[:fee_amount]).to eq(6.0)
    expect(details[:net_amount]).to eq(194.0)
  end

  it 'AC-4P5-03 Charge reference full-path from an already-expanded latest_charge object' do
    session = pi_session(external_id: 'pi_test_3', mode: true)
    charge = Charge.new('ch_test_3', 10_000, 'usd', 'txn_test_3')
    intent = PI.new('pi_test_3', 'succeeded', charge, 10_000, 'usd') # latest_charge already expanded object
    stub_intent(session, intent)
    allow(gateway).to receive(:retrieve_balance_transaction).with('txn_test_3')
                                                          .and_return(BT.new('txn_test_3', 0, 10_000, 'usd'))

    details = gateway.fetch_financial_details(payment_session: session)
    expect(details[:provider_charge_reference]).to eq('ch_test_3')
  end

  it 'AC-4P5-04 non-settled intent → settlement status mapped, fee/net nil, no guessing' do
    session = pi_session(external_id: 'pi_test_4', mode: true)
    intent = PI.new('pi_test_4', 'requires_capture', nil, 10_000, 'usd')
    stub_intent(session, intent)

    details = gateway.fetch_financial_details(payment_session: session)
    expect(details[:settlement_status]).to eq('requires_capture')
    expect(details[:gross_amount]).to eq(100.0)
    expect(details[:fee_amount]).to be_nil
    expect(details[:net_amount]).to be_nil
    expect(details[:provider_charge_reference]).to be_nil
    expect(details[:provider_refund_references]).to eq([])
  end

  it 'AC-4P5-05 no refunds → refund_total nil, empty refund references' do
    session = pi_session(external_id: 'pi_test_5', mode: true)
    intent = PI.new('pi_test_5', 'succeeded', 'ch_test_5', 10_000, 'usd')
    stub_intent(session, intent)
    charge = Charge.new('ch_test_5', 10_000, 'usd', 'txn_test_5')
    allow(gateway).to receive(:retrieve_charge).with('ch_test_5').and_return(charge)
    allow(gateway).to receive(:retrieve_balance_transaction).with('txn_test_5')
                                                          .and_return(BT.new('txn_test_5', 300, 9700, 'usd'))

    details = gateway.fetch_financial_details(payment_session: session)
    expect(details[:provider_refund_references]).to eq([])
    expect(details[:refund_total]).to be_nil
  end

  it 'AC-4P5-09 read-only: only retrieve/list calls, never mutation' do
    session = pi_session(external_id: 'pi_test_6', mode: true)
    intent = PI.new('pi_test_6', 'succeeded', 'ch_test_6', 10_000, 'usd')
    stub_intent(session, intent)
    charge = Charge.new('ch_test_6', 10_000, 'usd', 'txn_test_6')
    allow(gateway).to receive(:retrieve_charge).with('ch_test_6').and_return(charge)
    allow(gateway).to receive(:retrieve_balance_transaction).with('txn_test_6')
                                                          .and_return(BT.new('txn_test_6', 300, 9700, 'usd'))

    expect(Stripe::PaymentIntent).not_to receive(:confirm)
    expect(Stripe::Refund).not_to receive(:create)
    expect(Stripe::Charge).not_to receive(:capture)

    details = gateway.fetch_financial_details(payment_session: session)
    expect(details[:settlement_status]).to eq('settled')
  end

  it 'raises GatewayError when the session has no PaymentIntent' do
    session = pi_session(external_id: 'pi_test_7', mode: true)
    allow(gateway).to receive(:retrieve_payment_intent).and_return(nil)

    expect { gateway.fetch_financial_details(payment_session: session) }
      .to raise_error(PallasTrade::Core::GatewayError, /no PaymentIntent/)
  end
end
