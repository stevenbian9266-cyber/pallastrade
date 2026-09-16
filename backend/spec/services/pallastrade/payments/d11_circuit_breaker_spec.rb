# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d11-circuit-breaker-health（切片1，core 服务）
#   AC-003 ← FR-003：样本达标且失败率超阈值 → 自动软置灰（cooldown）+ 审计；
#                    到期自动恢复（写审计）；手动置灰不自动恢复；未达标不动（幂等）
RSpec.describe PallasTrade::Payments::CircuitBreaker::Evaluate, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order_with_line_items, store: store, shipment_cost: 0) }
  let(:now) { Time.current }

  before do
    payment_method.update_columns(
      private_metadata: {
        'breaker_thresholds' => { 'min_samples' => 2, 'failure_rate_threshold' => 0.5,
                                  'cooldown_seconds' => 60 }
      }
    )
  end

  def build_session(status)
    create(:bogus_payment_session, order: order, payment_method: payment_method, status: status)
  end

  def breaker_audits(action)
    PallasTrade::AuditLog.where(action: action, resource_type: payment_method.class.name)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-003
  it 'soft-disables the entry once the failure rate crosses the threshold' do
    build_session('failed')
    build_session('failed')
    build_session('completed')

    result = described_class.call(payment_method: payment_method, now: now)

    expect(result.success?).to be(true)
    expect(result.value[:opened]).to eq(['bogus'])
    expect(payment_method.soft_disabled?('bogus')).to be(true)

    state = payment_method.breaker_state('bogus')
    expect(state['manual']).to be(false)
    expect(state['sample_size']).to eq(3)
    expect(state['failure_rate']).to be_within(0.0001).of(0.6667)
    expect(Time.zone.parse(state['until'])).to be_within(2.seconds).of(now + 60.seconds)

    audit = breaker_audits('payment_option_auto_soft_disabled').last
    expect(audit).to be_present
    expect(audit.resource_id).to eq(payment_method.id)
    expect(audit.after['kind']).to eq('bogus')
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-003
  it 'leaves healthy providers and small samples untouched' do
    build_session('failed')
    build_session('completed')
    build_session('completed')
    build_session('completed')

    result = described_class.call(payment_method: payment_method, now: now)

    expect(result.value[:opened]).to be_empty
    expect(payment_method.soft_disabled?('bogus')).to be(false)
    expect(breaker_audits('payment_option_auto_soft_disabled').count).to eq(0)

    small_sample = described_class.call(payment_method: payment_method, now: now)
    expect(small_sample.value[:observed]).to eq([{ kind: 'bogus', attempts: 4, failure_rate: 0.25 }])
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-003
  it 'does not re-open an entry that is still inside its cooldown' do
    payment_method.soft_disable!(kind: 'bogus', until_at: now + 10.minutes, reason: 'auto')
    build_session('failed')
    build_session('failed')

    result = described_class.call(payment_method: payment_method, now: now)

    expect(result.value[:opened]).to be_empty
    expect(Time.zone.parse(payment_method.breaker_state('bogus')['until'])).to be_within(2.seconds).of(now + 10.minutes)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-003
  it 'restores an automatically soft-disabled entry once the cooldown elapses' do
    payment_method.soft_disable!(kind: 'bogus', until_at: now - 1.minute, reason: 'auto',
                                 failure_rate: 0.8, sample_size: 12)

    result = described_class.call(payment_method: payment_method, now: now)

    expect(result.value[:restored]).to eq(['bogus'])
    expect(payment_method.soft_disabled?('bogus')).to be(false)
    expect(payment_method.breaker_state('bogus')).to be_nil

    audit = breaker_audits('payment_option_breaker_restored').last
    expect(audit).to be_present
    expect(audit.after['kind']).to eq('bogus')
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-003
  it 'never auto-restores a manual soft-disable' do
    payment_method.soft_disable!(kind: 'bogus', reason: 'PSP incident', manual: true)
    provider_state = payment_method.breaker_state('bogus')
    payment_method.update_columns(
      private_metadata: payment_method.metadata.merge(
        'breaker' => provider_state.merge('until' => (now - 5.minutes).iso8601)
      )
    )

    result = described_class.call(payment_method: payment_method, now: now)

    expect(result.value[:restored]).to be_empty
    expect(payment_method.soft_disabled?('bogus')).to be(true)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-003
  it 'judges every active entry of an optionized provider separately' do
    optionized = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                               name: 'D11 optionized',
                                               metadata: {
                                                 'optionized' => true,
                                                 'options' => [
                                                   { 'kind' => 'card', 'active' => true, 'position' => 1 },
                                                   { 'kind' => 'klarna', 'active' => false, 'position' => 2 }
                                                 ],
                                                 'breaker_thresholds' => { 'min_samples' => 2,
                                                                           'failure_rate_threshold' => 0.5,
                                                                           'cooldown_seconds' => 60 }
                                               })
    2.times { create(:bogus_payment_session, order: order, payment_method: optionized, status: 'failed') }

    result = described_class.call(payment_method: optionized, now: now)

    # 自动判定样本是 provider 级 → 对全部「生效入口」生效；未启用入口不落状态。
    expect(result.value[:opened]).to eq(['card'])
    expect(optionized.soft_disabled?('card')).to be(true)
    expect(optionized.breaker_state('klarna')).to be_nil
  end
end
