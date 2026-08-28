# frozen_string_literal: true

require 'rails_helper'

# PRD-20260828-checkout-p8 AC-001/002/004/006：下单前置校验（Preflight，flag 灰度）
RSpec.describe PallasTrade::Checkout::Preflight, type: :service do
  let!(:store) { create(:store, code: 'preflight_store') }
  let(:user) { create(:user) }
  let(:order) { create(:order, store: store, user: user) }

  after { PallasTrade::Risk.rules = [] }

  describe '#call' do
    it 'AC-006 passes through when the flag is disabled (default)' do
      result = described_class.call(order: order)
      expect(result.success?).to be true
    end

    describe 'with flag enabled' do
      before { store.update!(preferred_checkout_preflight_enabled: true) }

      it 'AC-001 blocks a blacklisted user with a structured error' do
        PallasTrade::Risk.rules = [PallasTrade::Risk::BlacklistRule]
        user.update_column(:blacklisted_at, Time.current)

        result = described_class.call(order: order)

        expect(result.failure?).to be true
        expect(result.error.value).to eq({ code: 'user_blacklisted', message: 'Account is blacklisted' })
      end

      it 'AC-003 blocks when a custom risk rule matches' do
        rule_class = Class.new do
          def call(order:, user:, store:)
            { code: 'custom_rule_hit', message: 'Custom rule blocked' }
          end
        end
        PallasTrade::Risk.rules = [rule_class]

        result = described_class.call(order: order)

        expect(result.failure?).to be true
        expect(result.error.value[:code]).to eq('custom_rule_hit')
      end

      it 'AC-004 blocks when the order frequency limit is exceeded' do
        PallasTrade::Risk.rules = [PallasTrade::Risk::OrderFrequencyRule]
        store.update!(preferred_order_frequency_limit: 1)
        create(:order, store: store, user: user, state: 'complete', completed_at: Time.current)

        result = described_class.call(order: order)

        expect(result.failure?).to be true
        expect(result.error.value[:code]).to eq('order_frequency_limit')
      end

      it 'AC-006 allows a clean order through' do
        result = described_class.call(order: order)
        expect(result.success?).to be true
      end
    end
  end
end
