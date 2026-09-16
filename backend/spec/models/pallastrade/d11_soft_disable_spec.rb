# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d11-circuit-breaker-health（切片1，core 模型）
#   AC-001 ← FR-001：breaker 状态存取（选项化 → 入口级 metadata['options'][i]['breaker']；
#                    未选项化 → metadata['breaker']）+ 手动置灰粘性 + 自动到期失效
#   AC-005 ← FR-007：阈值可由 metadata['breaker_thresholds'] 覆盖，默认值稳定
RSpec.describe 'D11 payment method circuit breaker state', type: :model do
  let(:store) { @default_store }

  def optionized_provider(options, attributes = {})
    create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                  name: 'D11 provider',
                                  metadata: { 'optionized' => true, 'options' => options }, **attributes)
  end

  def plain_provider(attributes = {})
    create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                  name: 'Plain D11 provider', **attributes)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-001
  it 'soft-disables and re-enables a single entry of an optionized provider' do
    provider = optionized_provider([
      { 'kind' => 'card', 'active' => true, 'position' => 1 },
      { 'kind' => 'apple_pay', 'active' => true, 'position' => 2 }
    ])

    provider.soft_disable!(kind: 'card', until_at: 15.minutes.from_now, reason: 'auto',
                           failure_rate: 0.75, sample_size: 20)

    expect(provider.soft_disabled?('card')).to be(true)
    expect(provider.soft_disabled?('apple_pay')).to be(false)

    state = provider.breaker_state('card')
    expect(state['reason']).to eq('auto')
    expect(state['manual']).to be(false)
    expect(state['failure_rate']).to eq(0.75)
    expect(state['sample_size']).to eq(20)
    expect(state['opened_at']).to be_present

    # 置灰状态落 metadata（options 条目内嵌 breaker），其他入口不受影响
    options = provider.reload.metadata['options']
    expect(options.find { |option| option['kind'] == 'card' }['breaker']).to be_present
    expect(options.find { |option| option['kind'] == 'apple_pay' }['breaker']).to be_nil

    provider.soft_enable!('card')
    expect(provider.soft_disabled?('card')).to be(false)
    expect(provider.breaker_state('card')).to be_nil
    expect(provider.reload.metadata['options'].first).not_to have_key('breaker')
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-001
  it 'keeps manual soft-disables sticky until they are re-enabled by hand' do
    provider = plain_provider
    kind = provider.default_option_kind

    provider.soft_disable!(kind: kind, reason: 'PSP incident INC-42', manual: true)

    expect(provider.soft_disabled?(kind)).to be(true)
    expect(provider.breaker_state(kind)['until']).to be_nil
    expect(provider.soft_disabled?(kind, now: 10.years.from_now)).to be(true)

    provider.soft_enable!
    expect(provider.soft_disabled?(kind)).to be(false)
    expect(provider.reload.metadata['breaker']).to be_nil
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-001
  it 'expires automatic soft-disables once the cooldown elapses' do
    provider = plain_provider
    kind = provider.default_option_kind

    provider.soft_disable!(kind: kind, until_at: 15.minutes.from_now, reason: 'auto')

    expect(provider.soft_disabled?(kind, now: 10.minutes.from_now)).to be(true)
    expect(provider.soft_disabled?(kind, now: 20.minutes.from_now)).to be(false)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-005
  it 'exposes default breaker thresholds and honours provider overrides' do
    provider = plain_provider

    expect(provider.breaker_thresholds).to include(
      'min_samples' => 10, 'failure_rate_threshold' => 0.5, 'cooldown_seconds' => 900
    )

    overriding = plain_provider(metadata: { 'breaker_thresholds' => { 'min_samples' => 3,
                                                                     'failure_rate_threshold' => 0.25,
                                                                     'cooldown_seconds' => 60,
                                                                     'ignored' => 'x' } })

    expect(overriding.breaker_thresholds).to eq(
      'min_samples' => 3, 'failure_rate_threshold' => 0.25, 'cooldown_seconds' => 60
    )
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-001
  it 'treats malformed breaker timestamps as not soft-disabled' do
    provider = plain_provider
    kind = provider.default_option_kind
    provider.update_columns(private_metadata: { 'breaker' => { 'until' => 'not-a-time', 'reason' => 'x' } })

    expect(provider.soft_disabled?(kind)).to be(false)
  end
end
