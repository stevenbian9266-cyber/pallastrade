# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-payments-d12-webhook-governance（切片2，core 服务）
#   AC-005 ← FR-005：期望集 − 观察集 = 漏订候选；观察集 − 期望集 = 未声明事件
#   AC-006 ← FR-006：provider 声明（Stripe 覆盖其事件表；其他 provider 默认空集不报错）
RSpec.describe PallasTrade::Payments::WebhookSubscriptionChecklist, type: :service do
  let(:store) { @default_store }
  let(:stripe) { create(:stripe_gateway, store: store, active: true, display_on: 'both') }

  def build_event(provider:, action:, provider_event_id:, seconds_ago: 60)
    event = PallasTrade::PaymentWebhookEvent.create_unique(
      provider: provider, provider_event_id: provider_event_id,
      payment_method_id: stripe.id, action: action
    ).first
    event.update_columns(received_at: Time.current - seconds_ago)
    event
  end

  # PRD-20260915-payments-d12-webhook-governance AC-006
  it 'declares the Stripe subscription surface and maps it to local actions' do
    expect(stripe.webhook_event_subscriptions)
      .to include('payment_intent.succeeded', 'charge.dispute.created', 'checkout.session.completed')
    expect(stripe.webhook_expected_actions).to include('captured', 'authorized', 'failed', 'canceled')

    # 默认 provider 无声明（空集），不抛错
    expect(create(:bogus_payment_method, store: store).webhook_event_subscriptions).to eq([])
  end

  # PRD-20260915-payments-d12-webhook-governance AC-005
  it 'reports every declared action as missing until an event arrives' do
    stripe

    row = described_class.for_provider('stripe')

    expect(row[:configured]).to be(true)
    expect(row[:expected]).to eq(stripe.webhook_expected_actions.sort)
    expect(row[:observed]).to eq([])
    expect(row[:missing]).to eq(stripe.webhook_expected_actions.sort)
    expect(row[:unknown]).to eq([])
  end

  # PRD-20260915-payments-d12-webhook-governance AC-005
  it 'clears an action from the missing list once it has been received, and flags undeclared ones' do
    stripe
    build_event(provider: 'stripe', action: 'captured', provider_event_id: 'evt_captured')
    build_event(provider: 'stripe', action: 'failed', provider_event_id: 'evt_failed')
    # 未声明 provider（无配置）收到的事件 -> unknown
    build_event(provider: 'adyen', action: 'captured', provider_event_id: 'evt_adyen')

    stripe_row = described_class.for_provider('stripe')
    expect(stripe_row[:observed]).to include('captured', 'failed')
    expect(stripe_row[:missing]).not_to include('captured', 'failed')
    expect(stripe_row[:missing]).to include('canceled')

    adyen_row = described_class.for_provider('adyen')
    expect(adyen_row[:configured]).to be(false)
    expect(adyen_row[:expected]).to eq([])
    expect(adyen_row[:unknown]).to eq(['captured'])
  end

  # PRD-20260915-payments-d12-webhook-governance AC-005
  it 'ignores events outside the window and returns one row per provider' do
    stripe
    build_event(provider: 'stripe', action: 'captured', provider_event_id: 'evt_old', seconds_ago: 60.days.to_i)

    rows = described_class.call(window: 30.days)

    expect(rows.map { |row| row[:provider] }).to eq(['stripe'])
    expect(rows.first[:observed]).to eq([])
  end
end
