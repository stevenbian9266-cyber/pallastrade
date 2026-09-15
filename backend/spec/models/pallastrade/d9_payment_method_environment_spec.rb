# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-payments-d9-支付凭据与环境（切片1，core）
#   AC-001 ← FR-001/002：test 环境 provider 不进前台列表（后台录单不受限）；切回 live 立即恢复
#   AC-003 ← FR-003：凭据分级（secret / publishable / internal）+ `env:` 引用（只存引用、读取侧解析）
#   AC-005 读取侧 ← FR-005：credential_status（轮换 / 到期 / 告警级别）
# 调度与告警写入见 credential_expiry_check_job_spec.rb；Start 打标见 start_spec.rb（AC-002）。
RSpec.describe 'D9 environment + credential lifecycle', type: :model do
  let(:store) { create(:store, code: "d9_env_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD') }

  def check_provider(**attrs)
    create(:check_payment_method, store: store, active: true, display_on: 'both', **attrs)
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-001
  it 'keeps test-environment providers out of the storefront list (back-end unaffected)' do
    sandbox = check_provider(environment: 'test')
    live = check_provider
    order = create(:order_with_line_items, store: store)

    expect(order.collect_frontend_payment_methods).to include(live)
    expect(order.collect_frontend_payment_methods).not_to include(sandbox)
    # 后台录单不受环境限制（沙箱/培训可用）
    expect(order.collect_backend_payment_methods).to include(sandbox)

    sandbox.update!(environment: 'live')
    expect(order.reload.collect_frontend_payment_methods).to include(sandbox)
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-001
  it 'rejects unknown environments and treats legacy rows as live' do
    provider = check_provider
    expect(provider.live_environment?).to be(true)

    provider.environment = 'staging'
    expect(provider).not_to be_valid
    expect(provider.errors[:environment]).to be_present

    provider.update!(environment: 'test')
    expect(provider.test_environment?).to be(true)
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-003
  it 'classifies credentials as secret / publishable / internal' do
    bogus = create(:credit_card_payment_method, store: store)

    expect(bogus.credential_level(:dummy_secret_key)).to eq('secret')
    expect(bogus.credential_level(:dummy_key)).to eq('publishable')
    expect(bogus.credential_level(:no_such_key)).to eq('internal')
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-003
  it 'stores env: references without plaintext and resolves them on read' do
    provider = create(:credit_card_payment_method, store: store)
    provider.set_preference(:dummy_secret_key, 'env:D9_TEST_SECRET')
    provider.save!

    expect(provider.reload.preferences[:dummy_secret_key]).to eq('env:D9_TEST_SECRET')
    expect(provider.resolved_preference(:dummy_secret_key)).to be_nil

    ENV['D9_TEST_SECRET'] = 'sk_test_from_env'
    expect(provider.resolved_preference(:dummy_secret_key)).to eq('sk_test_from_env')

    # 非引用值原样返回（零回归）
    provider.set_preference(:dummy_secret_key, 'sk_live_plain')
    expect(provider.resolved_preference(:dummy_secret_key)).to eq('sk_live_plain')
  ensure
    ENV.delete('D9_TEST_SECRET')
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-005
  it 'computes credential status (rotation / expiry / alert level)' do
    provider = check_provider(
      metadata: {
        'credentials' => {
          'secret_key' => { 'rotated_at' => '2026-08-01T00:00:00Z', 'expires_on' => 10.days.from_now.to_date.iso8601 }
        }
      }
    )

    status = provider.credential_status(:secret_key)
    expect(status['rotated_at']).to eq('2026-08-01T00:00:00Z')
    expect(status['days_left']).to eq(10)
    expect(status['alert_level']).to eq('30d')

    # 7 天 / 1 天 / 过期 三档 + 无声明
    provider.update!(metadata: { 'credentials' => { 'secret_key' => { 'expires_on' => 5.days.from_now.to_date.iso8601 } } })
    expect(provider.credential_status(:secret_key)['alert_level']).to eq('7d')

    provider.update!(metadata: { 'credentials' => { 'secret_key' => { 'expires_on' => 1.day.from_now.to_date.iso8601 } } })
    expect(provider.credential_status(:secret_key)['alert_level']).to eq('1d')

    provider.update!(metadata: { 'credentials' => { 'secret_key' => { 'expires_on' => 3.days.ago.to_date.iso8601 } } })
    expect(provider.credential_status(:secret_key)['alert_level']).to eq('expired')

    provider.update!(metadata: {})
    expect(provider.credential_status(:secret_key)).to include('days_left' => nil, 'alert_level' => 'none')
  end
end
