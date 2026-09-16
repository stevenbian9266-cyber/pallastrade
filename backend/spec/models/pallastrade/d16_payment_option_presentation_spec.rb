# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d16-payment-method-presentation（切片1，core）
#   AC-001 ← FR-001/002：选项化 provider 的入口级展示元数据（display_name / method_key / option_id）
#   AC-002 ← FR-002：未配 display_name 或未选项化 → 回落 provider name（零回归）
RSpec.describe 'D16 payment option presentation', type: :model do
  let(:store) { @default_store }

  def optionized_provider(options)
    create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                  name: 'Check provider',
                                  metadata: { 'optionized' => true, 'options' => options })
  end

  # PRD-20260916-payments-d16-payment-method-presentation AC-001
  it 'exposes the configured storefront name and the entry-level identity' do
    provider = optionized_provider([
      { 'kind' => 'card', 'active' => true, 'position' => 1, 'display_name' => '信用卡' }
    ])

    expect(provider.effective_payment_option['kind']).to eq('card')
    expect(provider.option_display_name).to eq('信用卡')
    expect(provider.option_identifier).to eq("#{provider.prefixed_id}:card")
  end

  # PRD-20260916-payments-d16-payment-method-presentation AC-001
  it 'uses the first enabled entry by position when several are configured' do
    provider = optionized_provider([
      { 'kind' => 'apple_pay', 'active' => true, 'position' => 2, 'display_name' => 'Apple Pay' },
      { 'kind' => 'card', 'active' => true, 'position' => 1, 'display_name' => '信用卡' },
      { 'kind' => 'klarna', 'active' => false, 'position' => 0, 'display_name' => 'Klarna' }
    ])

    expect(provider.effective_payment_option['kind']).to eq('card')
    expect(provider.option_display_name).to eq('信用卡')
  end

  # PRD-20260916-payments-d16-payment-method-presentation AC-002
  it 'falls back to the provider name when no storefront name is configured' do
    provider = optionized_provider([
      { 'kind' => 'card', 'active' => true, 'position' => 1 }
    ])

    expect(provider.option_display_name).to eq('Check provider')
  end

  # PRD-20260916-payments-d16-payment-method-presentation AC-002
  it 'keeps the implicit default entry for providers that were never optionized' do
    provider = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                             name: 'Plain provider')

    expect(provider.optionized?).to be(false)
    expect(provider.option_display_name).to eq('Plain provider')
    expect(provider.effective_payment_option['kind']).to eq(provider.default_option_kind)
    expect(provider.option_identifier).to eq("#{provider.prefixed_id}:#{provider.default_option_kind}")
  end

  # PRD-20260916-payments-d16-payment-method-presentation AC-002
  it 'falls back to the default entry when an optionized provider has no enabled entry' do
    provider = optionized_provider([
      { 'kind' => 'card', 'active' => false, 'position' => 1, 'display_name' => 'Disabled' }
    ])

    expect(provider.effective_payment_option['kind']).to eq(provider.default_option_kind)
    expect(provider.option_display_name).to eq('Check provider')
  end
end
