# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-checkout-d15-切片3（D15 切片3，3DS/SCA 策略）
#   AC-001 ← FR-001：策略归一化（默认 risk_based / 三值合法 / 未知模式与非法阈值回落 + 记原因）
#   AC-002 ← FR-001：读路径永不抛错；写路径（storable）非法值 → errors 不落库
RSpec.describe PallasTrade::Payments::ThreeDSecure::Policy do
  let(:store) do
    create(:store, code: "d15c-policy-#{SecureRandom.hex(4)}", name: 'D15c Policy Store',
                   default: true, default_currency: 'USD', default_locale: 'en',
                   url: 'https://d15c-policy.example.com', mail_from_address: 'no-reply@d15c-policy.example.com')
  end

  def store_policy(attributes)
    store.update!(private_metadata: (store.private_metadata || {}).merge(
      described_class::STORE_METADATA_KEY => attributes
    ))
    store.reload
  end

  describe '.for' do
    # AC-001
    it 'defaults to risk_based when the store has no policy configured' do
      policy = described_class.for(store)

      expect(policy.mode).to eq('risk_based')
      expect(policy.risk_based?).to be(true)
      expect(policy.low_amount_threshold).to be_nil
      expect(policy.allowlisted_countries).to eq([])
      expect(policy.allowlisted_option_kinds).to eq([])
      expect(policy.reasons).to eq([])
      expect(described_class.configured_for?(store)).to be(false)
    end

    # AC-001
    it 'reads a stored policy and normalizes its values' do
      store_policy('mode' => 'always', 'low_amount_threshold' => '50.5',
                   'allowlisted_countries' => %w[de fr], 'allowlisted_option_kinds' => ['Card', ' apple_pay '])

      policy = described_class.for(store)

      expect(policy.mode).to eq('always')
      expect(policy.always?).to be(true)
      expect(policy.low_amount_threshold).to eq(BigDecimal('50.5'))
      expect(policy.allowlisted_countries).to eq(%w[DE FR])
      expect(policy.allowlisted_option_kinds).to eq(%w[card apple_pay])
      expect(policy.exemptions_configured?).to be(true)
      expect(described_class.configured_for?(store)).to be(true)
    end

    # AC-001（读路径 fail safe：写坏了也不抛错）
    it 'falls back to the default mode and records the reason for an unknown mode' do
      store_policy('mode' => 'sometimes')

      policy = described_class.for(store)

      expect(policy.mode).to eq('risk_based')
      expect(policy.reasons).to include('unknown_mode:sometimes')
    end

    # AC-001
    it 'drops a non-positive threshold and reports invalid country codes' do
      store_policy('mode' => 'always', 'low_amount_threshold' => '-5',
                   'allowlisted_countries' => ['DE', 'nope', 'F'])

      policy = described_class.for(store)

      expect(policy.low_amount_threshold).to be_nil
      expect(policy.reasons).to include('invalid_threshold')
      expect(policy.allowlisted_countries).to eq(%w[DE])
      expect(policy.reasons).to include('invalid_country:NOPE', 'invalid_country:F')
    end

    # AC-001（读取容错：JSON 字符串 / 完全缺失 / nil store 都不炸）
    it 'tolerates a JSON string, missing metadata and a nil store' do
      store.update!(private_metadata: (store.private_metadata || {}).merge(
        described_class::STORE_METADATA_KEY => '{"mode":"off"}'
      ))

      expect(described_class.for(store.reload).mode).to eq('off')
      expect(described_class.for(nil).mode).to eq('risk_based')
      expect(described_class.normalize(nil).mode).to eq('risk_based')
    end
  end

  describe '.storable' do
    # AC-002
    it 'returns normalized attributes and no errors for valid input' do
      attributes, errors = described_class.storable(
        'mode' => 'always', 'low_amount_threshold' => '10', 'allowlisted_countries' => 'de, FR',
        'allowlisted_option_kinds' => 'card'
      )

      expect(errors).to eq([])
      expect(attributes['mode']).to eq('always')
      expect(attributes['low_amount_threshold']).to eq('10.0')
      expect(attributes['allowlisted_countries']).to eq(%w[DE FR])
      expect(attributes['allowlisted_option_kinds']).to eq(%w[card])
    end

    # AC-002（写路径拒绝非法值）
    it 'rejects an unknown mode, a non-positive threshold and invalid country codes' do
      _attributes, errors = described_class.storable(
        'mode' => 'sometimes', 'low_amount_threshold' => '0', 'allowlisted_countries' => 'DE,nope'
      )

      expect(errors).to include('unknown_mode:sometimes', 'invalid_threshold', 'invalid_country:NOPE')
    end

    # AC-002
    it 'defaults the mode when blank and never returns nil attributes' do
      attributes, errors = described_class.storable({})

      expect(errors).to eq([])
      expect(attributes).to eq(
        'mode' => 'risk_based', 'low_amount_threshold' => nil,
        'allowlisted_countries' => [], 'allowlisted_option_kinds' => []
      )
    end
  end
end
