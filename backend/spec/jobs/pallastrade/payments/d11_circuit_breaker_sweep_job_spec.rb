# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d11-circuit-breaker-health（切片1，core 作业）
#   AC-004 ← FR-004：巡检作业遍历 active provider（单 provider 失败不中断整体）+ 幂等
RSpec.describe PallasTrade::Payments::CircuitBreaker::SweepJob, type: :job do
  let(:store) { @default_store }
  let(:order) { create(:order_with_line_items, store: store, shipment_cost: 0) }
  let(:now) { Time.current }

  def failing_provider(name)
    provider = create(:check_payment_method, store: store, active: true, display_on: 'front_end', name: name)
    provider.update_columns(
      private_metadata: { 'breaker_thresholds' => { 'min_samples' => 2, 'failure_rate_threshold' => 0.5,
                                                     'cooldown_seconds' => 60 } }
    )
    provider
  end

  def open_kinds(provider)
    ["#{provider.id}:#{provider.default_option_kind}"]
  end

  # rspec-retry 会重跑失败用例（不 rollback），这里显式从干净状态开始，保证可重跑。
  def clean_breaker!(provider)
    provider.soft_enable!(provider.default_option_kind)
    provider.reload
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-004
  it 'soft-disables every degraded provider and reports a summary', retry: 0 do
    degraded = clean_breaker!(failing_provider('D11 degraded'))
    healthy = clean_breaker!(failing_provider('D11 healthy'))
    2.times { create(:bogus_payment_session, order: order, payment_method: degraded, status: 'failed') }
    2.times { create(:bogus_payment_session, order: order, payment_method: healthy, status: 'completed') }

    summary = described_class.new.perform(now: now)

    expect(summary[:opened]).to eq(open_kinds(degraded))
    expect(summary[:restored]).to eq([])
    expect(degraded.reload.soft_disabled?('check')).to be(true)
    expect(healthy.reload.soft_disabled?('check')).to be(false)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-004
  it 'is idempotent and skips inactive providers', retry: 0 do
    degraded = clean_breaker!(failing_provider('D11 idle'))
    2.times { create(:bogus_payment_session, order: order, payment_method: degraded, status: 'failed') }
    inactive = clean_breaker!(failing_provider('D11 inactive'))
    inactive.update_column(:active, false)
    2.times { create(:bogus_payment_session, order: order, payment_method: inactive, status: 'failed') }

    first = described_class.new.perform(now: now)
    second = described_class.new.perform(now: now + 1.minute)

    expect(first[:opened]).to eq(open_kinds(degraded))
    expect(second[:opened]).to eq([])
    expect(inactive.reload.soft_disabled?('check')).to be(false)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-004
  it 'keeps sweeping when a single provider raises', retry: 0 do
    working = clean_breaker!(failing_provider('D11 working'))
    2.times { create(:bogus_payment_session, order: order, payment_method: working, status: 'failed') }
    broken = clean_breaker!(failing_provider('D11 broken'))
    broken_id = broken.id
    allow(PallasTrade::Payments::Health::Metrics).to receive(:call).and_wrap_original do |original, **kwargs|
      raise 'boom' if kwargs[:payment_method].id == broken_id

      original.call(**kwargs)
    end

    summary = described_class.new.perform(now: now)

    expect(summary[:opened]).to eq(open_kinds(working))
  end
end
