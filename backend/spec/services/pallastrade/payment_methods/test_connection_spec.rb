# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-admin-管理后台支付配置选项化（切片3）—— AC-004：凭证体检（Test connection）服务语义
#   本地体检（凭证齐备性）→ provider 远端探测（stub 覆盖）→ 报告归一 { ok, code, message, checked_at }。
# 安全：报告 message 脱敏（凭证原文 → [FILTERED]），日志只记 id/code。
RSpec.describe PallasTrade::PaymentMethods::TestConnection do
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }

  def stripe_gateway(**attrs)
    create(:stripe_gateway, store: store, **attrs)
  end

  def run(payment_method)
    described_class.call(payment_method: payment_method)
  end

  it 'returns a success result with a normalized report' do
    # PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 AC-004
    outcome = run(stripe_gateway)
    report = outcome.value

    expect(outcome).to be_success
    expect(report['ok']).to be(true)
    expect(report['code']).to eq('credentials_present')
    expect(Time.iso8601(report['checked_at'])).to be_present
  end

  it 'fails fast without a payment method' do
    outcome = run(nil)

    expect(outcome).to be_failure
    expect(outcome.error.to_s).to include('Payment method is required')
  end

  it 'reports providers that need no credentials as ok' do
    outcome = run(create(:check_payment_method, store: store))

    expect(outcome.value['ok']).to be(true)
    expect(outcome.value['code']).to eq('no_credentials_required')
  end

  it 'reports missing credentials without guessing values' do
    gateway = build(:stripe_gateway, store: store, preferences: { publishable_key: 'pk_test_1234', secret_key: '' })

    outcome = run(gateway)

    expect(outcome.value['ok']).to be(false)
    expect(outcome.value['code']).to eq('missing_credentials')
    expect(outcome.value['message']).to include('secret_key')
  end

  it 'uses a successful provider probe verbatim' do
    gateway = stripe_gateway
    allow(gateway).to receive(:test_connection).and_return({ ok: true, code: 'balance_ok', message: 'Reachable' })

    outcome = run(gateway)

    expect(outcome.value['ok']).to be(true)
    expect(outcome.value['code']).to eq('balance_ok')
    expect(outcome.value['message']).to eq('Reachable')
  end

  it 'normalizes a failed provider probe' do
    gateway = stripe_gateway
    allow(gateway).to receive(:test_connection).and_return({ ok: false, code: 'invalid_credentials', message: 'Bad key' })

    outcome = run(gateway)

    expect(outcome.value['ok']).to be(false)
    expect(outcome.value['code']).to eq('invalid_credentials')
  end

  it 'treats a bare false probe as probe_failed' do
    gateway = stripe_gateway
    allow(gateway).to receive(:test_connection).and_return(false)

    outcome = run(gateway)

    expect(outcome.value['ok']).to be(false)
    expect(outcome.value['code']).to eq('probe_failed')
  end

  it 'classifies network errors as network_unreachable' do
    gateway = stripe_gateway
    allow(gateway).to receive(:test_connection).and_raise(Errno::ECONNREFUSED.new('Connection refused'))

    outcome = run(gateway)

    expect(outcome.value['ok']).to be(false)
    expect(outcome.value['code']).to eq('network_unreachable')
  end

  it 'classifies other provider errors as probe_error' do
    gateway = stripe_gateway
    allow(gateway).to receive(:test_connection).and_raise('unexpected boom')

    outcome = run(gateway)

    expect(outcome.value['ok']).to be(false)
    expect(outcome.value['code']).to eq('probe_error')
  end

  it 'sanitizes credential values out of provider error messages' do
    gateway = stripe_gateway
    secret = gateway.preferences[:secret_key]
    allow(gateway).to receive(:test_connection).and_raise(StandardError, "rejected #{secret} (invalid)")

    outcome = run(gateway)

    expect(outcome.value['message']).to include('[FILTERED]')
    expect(outcome.value['message']).not_to include(secret)
  end
end
