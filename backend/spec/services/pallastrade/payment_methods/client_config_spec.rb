# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-payments-d10-client-config（切片1，core）
#   AC-002 ← FR-002：`ClientConfig.call` 输出 provider / environment / publishable / session_token
#   AC-003 ← FR-005：secret / internal 级凭据**永不**进入下发面
#   AC-004 ← FR-002：`env:NAME` 引用解析；ENV 缺失 → 省略该键（不抛错、不落明文）
RSpec.describe PallasTrade::PaymentMethods::ClientConfig, type: :service do
  let(:store) { create(:store, code: "d10_cc_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD') }

  def stripe_gateway(**attrs)
    create(:stripe_gateway, store: store, active: true, display_on: 'both', **attrs)
  end

  def bogus_gateway(**attrs)
    create(:credit_card_payment_method, store: store, active: true, display_on: 'both', **attrs)
  end

  # PRD-20260915-payments-d10-client-config AC-002
  it 'builds the client_config envelope (provider / environment / publishable / session_token)' do
    gateway = stripe_gateway
    gateway.set_preference(:publishable_key, 'pk_test_d10_envelope')
    gateway.save!

    config = described_class.call(gateway.reload)

    expect(config[:provider]).to eq('stripe')
    expect(config[:environment]).to eq('live')
    expect(config[:publishable]).to eq('publishable_key' => 'pk_test_d10_envelope')
    # 短时令牌是预留位（provider 侧签发属后续批次）
    expect(config[:session_token]).to be_nil
    expect(config.keys).to contain_exactly(:provider, :environment, :publishable, :session_token)
  end

  # PRD-20260915-payments-d10-client-config AC-002
  it 'reflects the D9 environment so the frontend can tell test from live' do
    gateway = stripe_gateway(environment: 'test')
    gateway.set_preference(:publishable_key, 'pk_test_d10_sandbox')
    gateway.save!

    expect(described_class.call(gateway.reload)[:environment]).to eq('test')
  end

  # PRD-20260915-payments-d10-client-config AC-003
  it 'never exposes secret or internal credentials' do
    gateway = stripe_gateway
    gateway.set_preference(:publishable_key, 'pk_test_d10_visible')
    gateway.set_preference(:secret_key, 'sk_test_d10_must_not_leak')
    gateway.save!

    payload = described_class.call(gateway.reload)

    expect(payload[:publishable].keys).to eq(['publishable_key'])
    expect(payload[:publishable]).not_to have_key('secret_key')
    expect(payload.to_s).not_to include('sk_test_d10_must_not_leak')
    # internal 级（既非 publishable 也非 password）同样不下发
    expect(gateway.credential_level(:secret_key)).to eq('secret')
    expect(gateway.credential_level(:publishable_key)).to eq('publishable')
  end

  # PRD-20260915-payments-d10-client-config AC-004
  it 'resolves env: references without persisting plaintext' do
    gateway = stripe_gateway
    gateway.set_preference(:publishable_key, 'env:D10_STRIPE_PUBLISHABLE')
    gateway.save!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('D10_STRIPE_PUBLISHABLE').and_return('pk_env_d10')

    expect(gateway.reload.preferences[:publishable_key]).to eq('env:D10_STRIPE_PUBLISHABLE')
    expect(described_class.call(gateway)[:publishable]).to eq('publishable_key' => 'pk_env_d10')
  end

  # PRD-20260915-payments-d10-client-config AC-004
  it 'omits publishable keys whose env: reference cannot be resolved' do
    gateway = stripe_gateway
    gateway.set_preference(:publishable_key, 'env:D10_MISSING_PUBLISHABLE')
    gateway.save!

    config = described_class.call(gateway.reload)

    expect(config[:publishable]).to eq({})
    expect(config.to_s).not_to include('env:D10_MISSING_PUBLISHABLE')
  end

  # PRD-20260915-payments-d10-client-config AC-002
  it 'keeps the envelope shape for providers whose declared public credential is unset' do
    config = described_class.call(bogus_gateway)

    expect(config[:provider]).to eq('bogus')
    expect(config[:environment]).to eq('live')
    expect(config[:publishable]).to be_a(Hash)
    # 只考虑 provider 声明的公开键（Bogus 声明 [:dummy_key]），不泄漏其它偏好
    expect(config[:publishable].keys - ['dummy_key']).to eq([])
  end
end
