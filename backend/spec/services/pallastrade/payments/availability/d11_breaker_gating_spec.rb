# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d11-circuit-breaker-health（切片1，前台可用性）
#   AC-006 ← FR-005：软置灰入口从「可用入口」中消失（前台列表与 Start 同源），
#                    解除后立即恢复；`evaluate` 暴露 breaker_open 原因
RSpec.describe PallasTrade::Payments::Availability::Resolver, 'D11 breaker gating' do
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }
  let(:order) { create(:order_with_line_items, store: store) }

  def optionized_provider(options)
    create(:check_payment_method, store: store, active: true, display_on: 'front_end', name: 'D11 storefront',
                                  metadata: { 'optionized' => true, 'options' => options })
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-006
  it 'drops a soft-disabled entry from the available options and restores it on enable' do
    provider = optionized_provider([
      { 'kind' => 'card', 'active' => true, 'position' => 1 },
      { 'kind' => 'apple_pay', 'active' => true, 'position' => 2 }
    ])

    expect(described_class.available_option_kinds(order: order, payment_method: provider)).to eq(%w[card apple_pay])

    provider.soft_disable!(kind: 'card', until_at: 15.minutes.from_now, reason: 'auto')

    expect(described_class.available_option_kinds(order: order, payment_method: provider)).to eq(%w[apple_pay])
    expect(described_class.available_option_kinds(
      order: order, payment_method: provider,
      context: PallasTrade::Payments::Availability::Context.new
    )).to eq(%w[apple_pay])

    provider.soft_enable!('card')

    expect(described_class.available_option_kinds(order: order, payment_method: provider)).to eq(%w[card apple_pay])
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-006
  it 'reports breaker_open as the reason for a soft-disabled entry' do
    provider = optionized_provider([{ 'kind' => 'card', 'active' => true, 'position' => 1 }])
    provider.soft_disable!(kind: 'card', reason: 'PSP incident', manual: true)

    outcome = described_class.evaluate(order: order, payment_method: provider).first

    expect(outcome['allowed']).to be(false)
    expect(outcome['reasons']).to include({ 'dimension' => 'breaker', 'reason' => 'breaker_open' })
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-006
  it 'removes a fully softened provider from the frontend list while keeping others' do
    affected = optionized_provider([{ 'kind' => 'card', 'active' => true, 'position' => 1 }])
    untouched = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                              name: 'D11 untouched')
    affected.soft_disable!(kind: 'card', reason: 'PSP incident', manual: true)

    names = described_class.providers(order: order, scope: :frontend).map(&:name)

    expect(described_class.provider_available?(order: order, payment_method: affected)).to be(false)
    expect(names).not_to include('D11 storefront')
    expect(names).to include('D11 untouched')
    expect(described_class.available_option_kinds(order: order, payment_method: untouched)).
      to eq([untouched.default_option_kind])
  end
end
