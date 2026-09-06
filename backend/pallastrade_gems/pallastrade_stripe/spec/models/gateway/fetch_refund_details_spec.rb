# frozen_string_literal: true

require 'spec_helper'

# PRD-20260906-payments-fin-p4-6 AC-4P6-06: Stripe fetch_refund_details 只读归一
RSpec.describe PallasTradeStripe::Gateway, type: :model do
  subject(:gateway) { create(:stripe_gateway) }

  StripeRefund = Struct.new(:id, :amount, :currency, :status)

  before do
    Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', 'sk_test_placeholder')
  end

  def fake_refund
    double('refund', transaction_id: 're_stripe_1', amount: 20.0, currency: 'USD')
  end

  it 'normalizes a Stripe Refund (re_ id + amount cents→major + status)' do
    allow(gateway).to receive(:retrieve_refund).with('re_stripe_1').and_return(
      StripeRefund.new('re_stripe_1', 2000, 'usd', 'succeeded')
    )

    details = gateway.fetch_refund_details(refund: fake_refund)
    expect(details[:provider_refund_reference]).to eq('re_stripe_1')
    expect(details[:amount]).to eq(20.0)
    expect(details[:currency]).to eq('usd')
    expect(details[:status]).to eq('succeeded')
  end

  it 'raises GatewayError when the refund has no provider reference' do
    refund = double('refund', transaction_id: nil)
    expect { gateway.fetch_refund_details(refund: refund) }
      .to raise_error(PallasTrade::Core::GatewayError, /no provider refund reference/)
  end

  it 'is read-only: only Refund.retrieve, never mutation' do
    allow(gateway).to receive(:retrieve_refund).and_return(StripeRefund.new('re_stripe_1', 2000, 'usd', 'succeeded'))
    expect(Stripe::Refund).not_to receive(:create)

    details = gateway.fetch_refund_details(refund: fake_refund)
    expect(details[:amount]).to eq(20.0)
  end
end
