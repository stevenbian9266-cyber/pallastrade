# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-checkout-d15-切片3（D15 切片3，建会话门禁 + provider 下发）
#   AC-009 ← FR-004：不合规入口 → 422 `payment_option_not_available` + reason，且**零 session 行**
#   AC-012 ← FR-006：要求认证且真的建了会话 → 恰好发布一次事件（无 PII）
#   AC-013 ← FR-007：对声明了能力的入口透传 `three_d_secure` 指令（否则不下发、不猜）
RSpec.describe PallasTrade::PaymentSessions::Start, 'D15c authentication gate' do
  let(:store) do
    create(:store, code: "d15c-start-#{SecureRandom.hex(4)}", name: 'D15c Start Store',
                   default: false, default_currency: 'USD', default_locale: 'en',
                   url: 'https://d15c-start.example.com', mail_from_address: 'no-reply@d15c-start.example.com')
  end
  let(:order) { create(:order_with_line_items, store: store, line_items_price: 100, shipment_cost: 0) }

  # 离线 provider（Bogus）：`create_payment_session` 不碰网络；入口目录按需 stub
  def offline_provider(kinds: %w[card apple_pay])
    provider = create(:bogus_payment_method, store: store, active: true, display_on: 'front_end',
                                             name: "D15c start #{SecureRandom.hex(3)}",
                                             metadata: {
                                               'optionized' => true,
                                               'options' => kinds.each_with_index.map do |kind, index|
                                                 { 'kind' => kind, 'active' => true, 'position' => index + 1 }
                                               end
                                             })
    catalog = kinds.map do |kind|
      { 'kind' => kind, 'frontend_kind' => kind == 'card' ? 'inline' : 'express',
        'display_name' => kind, 'three_d_secure' => kind == 'card' ? 'supported' : 'unsupported' }
    end
    allow(provider).to receive(:payment_option_catalog).and_return(catalog)
    provider
  end

  def require_authentication!
    store.update!(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Payments::ThreeDSecure::Policy::STORE_METADATA_KEY => { 'mode' => 'always' }
    ))
    store.reload
    order.reload
    PallasTrade::Payments::ThreeDSecure::Required.reset_cache_for(order)
  end

  def capture_session_data(provider)
    captured = {}
    allow(provider).to receive(:create_payment_session).and_wrap_original do |original, **kwargs|
      captured[:external_data] = kwargs[:external_data]
      original.call(**kwargs)
    end
    captured
  end

  # AC-009（不合规入口：建会话前拒绝 + 零 session 行）
  it 'refuses an entry that cannot force authentication without creating a session' do
    provider = offline_provider
    require_authentication!

    expect do
      outcome = described_class.call(order: order, payment_method: provider, option_kind: 'apple_pay')

      expect(outcome).not_to be_success
      expect(outcome.error.value).to include(code: 'payment_option_not_available',
                                             reason: 'authentication_required')
    end.not_to change(PallasTrade::PaymentSession, :count)
  end

  # AC-009（provider 未传 option_kind：整条 provider 无可用入口 → 同样拒绝）
  it 'refuses the provider when none of its entries can authenticate' do
    provider = offline_provider(kinds: %w[apple_pay])
    require_authentication!

    outcome = described_class.call(order: order, payment_method: provider)

    expect(outcome).not_to be_success
    expect(outcome.error.value).to include(code: 'payment_option_not_available',
                                           reason: 'authentication_required')
  end

  # AC-010 + AC-013（合规入口：正常建会话 + 下发强制 3DS 指令）
  it 'creates the session for an entry that can authenticate and passes the provider hint' do
    provider = offline_provider
    require_authentication!
    captured = capture_session_data(provider)

    outcome = described_class.call(order: order, payment_method: provider, option_kind: 'card')

    expect(outcome).to be_success
    expect(captured[:external_data]).to include('three_d_secure' => true, 'three_d_secure_hint' => 'three_d_secure')
    expect(PallasTrade::PaymentSession.count).to eq(1)
  end

  # AC-010（不要求认证 → 零影响：不下发任何 3DS 指令）
  it 'passes no authentication hint when authentication is not required' do
    provider = offline_provider
    captured = capture_session_data(provider)

    outcome = described_class.call(order: order, payment_method: provider, option_kind: 'apple_pay')

    expect(outcome).to be_success
    expect(captured[:external_data]).not_to have_key('three_d_secure')
    expect(captured[:external_data]).not_to have_key('three_d_secure_hint')
  end

  # AC-012（事件恰好一次，payload 无 PII）
  it 'publishes the authentication event once with a PII-free payload' do
    provider = offline_provider
    require_authentication!
    published = []
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
    allow(PallasTrade::Events).to receive(:publish) { |name, payload| published << [name, payload] }

    described_class.call(order: order, payment_method: provider, option_kind: 'card')

    auth_events = published.select { |name, _| name == 'payment.three_d_secure_required' }
    expect(auth_events.size).to eq(1)
    payload = auth_events.first.last[:payload]
    expect(payload).to include('order_id' => order.id, 'mode' => 'always', 'source' => 'policy',
                               'provider_hint' => 'three_d_secure')
    expect(payload.keys).not_to include('email', 'last_ip_address', 'card')
  end

  # AC-012（不要求认证 → 不发事件）
  it 'does not publish the authentication event when authentication is not required' do
    provider = offline_provider
    published = []
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
    allow(PallasTrade::Events).to receive(:publish) { |name, _| published << name }

    described_class.call(order: order, payment_method: provider, option_kind: 'apple_pay')

    expect(published).not_to include('payment.three_d_secure_required')
  end
end
