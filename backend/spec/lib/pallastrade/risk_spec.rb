# frozen_string_literal: true

require 'rails_helper'

# PRD-20260828-checkout-p8 AC-003：风控规则引擎（注册/评估/首个命中）
RSpec.describe PallasTrade::Risk, type: :model do
  let!(:store) { create(:store, code: 'risk_store') }
  let(:user) { create(:user) }
  let(:order) { create(:order, store: store, user: user) }

  # 测试专用规则
  let(:custom_rule_class) do
    Class.new do
      def call(order:, user:, store:)
        return nil unless user&.email == 'blocked@example.com'

        { code: 'custom_rule_hit', message: 'Custom rule blocked' }
      end
    end
  end

  after { described_class.rules = [] }

  describe '#evaluate' do
    it 'AC-003 returns nil when no rules are registered' do
      expect(described_class.evaluate(order: order)).to be_nil
    end

    it 'AC-003 evaluates the first matching rule and returns its code + message' do
      described_class.rules = [custom_rule_class]
      blocked = create(:user, email: 'blocked@example.com')

      result = described_class.evaluate(order: order, user: blocked)

      expect(result).to eq({ code: 'custom_rule_hit', message: 'Custom rule blocked' })
    end

    it 'AC-003 skips non-matching rules and returns nil' do
      described_class.rules = [custom_rule_class]

      expect(described_class.evaluate(order: order, user: user)).to be_nil
    end

    it 'AC-001 BlacklistRule blocks users with blacklisted_at set' do
      described_class.rules = [PallasTrade::Risk::BlacklistRule]
      user.update_column(:blacklisted_at, Time.current)

      result = described_class.evaluate(order: order, user: user)

      expect(result).to eq({ code: 'user_blacklisted', message: 'Account is blacklisted' })
    end

    it 'AC-001 BlacklistRule allows users without blacklisted_at' do
      described_class.rules = [PallasTrade::Risk::BlacklistRule]

      expect(described_class.evaluate(order: order, user: user)).to be_nil
    end

    it 'AC-004 OrderFrequencyRule blocks when completed orders exceed the limit' do
      described_class.rules = [PallasTrade::Risk::OrderFrequencyRule]
      store.update!(preferred_order_frequency_limit: 2)
      3.times { create(:order, store: store, user: user, state: 'complete', completed_at: Time.current) }

      result = described_class.evaluate(order: order, user: user, store: store)

      expect(result[:code]).to eq('order_frequency_limit')
    end

    it 'AC-004 OrderFrequencyRule allows when under the limit (and default nil = off)' do
      described_class.rules = [PallasTrade::Risk::OrderFrequencyRule]
      store.update!(preferred_order_frequency_limit: 5)
      create(:order, store: store, user: user, state: 'complete', completed_at: Time.current)

      expect(described_class.evaluate(order: order, user: user, store: store)).to be_nil

      # 默认 limit nil = 关闭
      store.update!(preferred_order_frequency_limit: nil)
      3.times { create(:order, store: store, user: user, state: 'complete', completed_at: Time.current) }
      expect(described_class.evaluate(order: order, user: user, store: store)).to be_nil
    end
  end
end
