# frozen_string_literal: true

require 'rails_helper'

# CORE-P5-8 FR-001/AC-001/AC-011：OperationalMetrics 输出约定与故障隔离
RSpec.describe PallasTrade::OperationalMetrics, type: :service do
  let(:logged) { [] }
  let(:logger) do
    instance_double(Logger).tap do |double|
      allow(double).to receive(:info) { |msg| logged << msg }
    end
  end

  before { allow(Rails).to receive(:logger).and_return(logger) }

  describe '.count' do
    it 'AC-001 outputs a JSON line containing event, at timestamp and fields' do
      described_class.count('commerce_transaction.manual_review', transaction_id: 'txn_x', state: 'manual_review')

      expect(logged.size).to eq(1)
      parsed = JSON.parse(logged.first)
      expect(parsed['event']).to eq('commerce_transaction.manual_review')
      expect(parsed['transaction_id']).to eq('txn_x')
      expect(parsed['state']).to eq('manual_review')
      expect(parsed['at']).to be_present
    end
  end

  describe '.legacy' do
    it 'AC-001 maps to event "legacy.<metric>.calls"' do
      described_class.legacy('checkout_complete', order_id: 'or_x')

      expect(logged.size).to eq(1)
      parsed = JSON.parse(logged.first)
      expect(parsed['event']).to eq('legacy.checkout_complete.calls')
      expect(parsed['order_id']).to eq('or_x')
    end
  end

  describe 'failure isolation' do
    it 'AC-011 never raises when the logger raises' do
      allow(logger).to receive(:info).and_raise('boom')

      expect { described_class.count('legacy.x', a: 1) }.not_to raise_error
      expect { described_class.legacy('x', a: 1) }.not_to raise_error
    end
  end
end
