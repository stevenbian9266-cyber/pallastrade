# frozen_string_literal: true

require 'spec_helper'

# PRD-20260917-checkout-d15-切片3（D15 切片3，provider 下发）
#   AC-013 ← FR-007：要求认证 + 入口声明能力 → 载荷含 `request_three_d_secure='any'`；
#                    未要求 → 载荷不变（零回归）；能力缺失按不支持（不下发）
RSpec.describe 'Stripe 3DS hint (D15c)' do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 100, total: 100, payment_state: 'balance_due', currency: 'USD')
  end
  let(:gateway) { create(:stripe_gateway, store: store, active: true) }

  describe PallasTrade::Payments::ThreeDSecure::ProviderHint do
    # AC-013（真实 Stripe 目录：card supported / wallets unsupported）
    it 'reads the capability from the provider catalog without guessing' do
      expect(described_class.option_supported?(gateway, 'card')).to be(true)
      expect(described_class.option_supported?(gateway, 'apple_pay')).to be(false)
      expect(described_class.option_supported?(gateway, 'google_pay')).to be(false)
      expect(described_class.option_supported?(gateway, 'not_in_catalog')).to be(false)
      expect(described_class.option_supported?(nil, 'card')).to be(false)
    end

    # AC-013
    it 'applies the hint only for a capable entry when authentication is required' do
      applied = described_class.call(payment_method: gateway, option_kind: 'card', required: true).value
      wallet = described_class.call(payment_method: gateway, option_kind: 'apple_pay', required: true).value
      not_required = described_class.call(payment_method: gateway, option_kind: 'card', required: false).value

      expect(applied).to include('applied' => true, 'hint' => 'three_d_secure',
                                 'external_data' => { 'three_d_secure' => true })
      expect(wallet).to include('applied' => false, 'hint' => 'none', 'external_data' => {},
                                'reason' => 'provider_unsupported')
      expect(not_required).to include('applied' => false, 'hint' => 'none', 'external_data' => {},
                                      'reason' => 'not_required')
    end
  end

  describe PallasTradeStripe::CheckoutSessionPresenter do
    def session_payload(three_d_secure:)
      described_class.new(amount_in_cents: 10_000, order: order, three_d_secure: three_d_secure).call
    end

    # AC-013（Checkout Session 路径）
    it 'requests 3DS on the payment intent when forced' do
      payload = session_payload(three_d_secure: true)

      expect(payload[:payment_intent_data][:payment_method_options][:card][:request_three_d_secure]).to eq('any')
    end

    # AC-013（不要求 → 载荷不变）
    it 'leaves the payload untouched when not forced' do
      payload = session_payload(three_d_secure: false)

      expect(payload[:payment_intent_data]).not_to have_key(:payment_method_options)
    end
  end

  describe PallasTradeStripe::PaymentIntentPresenter do
    def intent_payload(three_d_secure:)
      described_class.new(amount: 10_000, order: order, three_d_secure: three_d_secure).call
    end

    # AC-013（自绘卡 PaymentIntent 路径）
    it 'requests 3DS on the card payment method options when forced' do
      card = intent_payload(three_d_secure: true)[:payment_method_options][:card]

      expect(card[:request_three_d_secure]).to eq('any')
      expect(card[:setup_future_usage]).to eq('off_session')
    end

    # AC-013（不要求 → 载荷不变）
    it 'keeps the card options unchanged when not forced' do
      card = intent_payload(three_d_secure: false)[:payment_method_options][:card]

      expect(card).to eq(setup_future_usage: 'off_session')
    end
  end
end
