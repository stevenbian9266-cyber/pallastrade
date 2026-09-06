# frozen_string_literal: true

require 'rails_helper'

# CORE-P5-8 FR-009/AC-009：事件级计数 subscriber（recovery_required / manual_review）
RSpec.describe PallasTrade::OperationalMetricsSubscriber, type: :subscriber do
  let(:logged) { [] }
  let(:logger) do
    instance_double(Logger).tap do |double|
      allow(double).to receive(:info) { |msg| logged << msg }
    end
  end
  let(:event) { double('event', name: 'commerce_transaction.recovery_required', payload: { 'id' => 'txn_x' }) }

  before { allow(Rails).to receive(:logger).and_return(logger) }

  it 'AC-009 subscribes to recovery_required and manual_review synchronously' do
    expect(described_class.subscription_patterns).to contain_exactly(
      'commerce_transaction.recovery_required',
      'commerce_transaction.manual_review'
    )
    expect(described_class.subscription_options[:async]).to eq(false)
  end

  it 'AC-009 emits a JSON count line carrying the event name and transaction id' do
    described_class.new.send(:count_event, event)

    expect(logged.size).to eq(1)
    parsed = JSON.parse(logged.first)
    expect(parsed['event']).to eq('commerce_transaction.recovery_required')
    expect(parsed['transaction_id']).to eq('txn_x')
  end
end
