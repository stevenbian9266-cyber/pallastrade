# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4，订阅者接线）
#   AC-6 ← FR-3：order.submitted → 锁汇快照；payload 三种形态兼容；同币种/无汇率不写行；异常不阻断下单
RSpec.describe PallasTrade::Currencies::Fx::OrderSubmittedSubscriber, type: :subscriber do
  let!(:store) do
    create(:store, code: "d13d_sub_#{SecureRandom.hex(4)}", default_currency: 'USD',
                   supported_currencies: 'USD,CNY')
  end
  let!(:order) { create(:order, store: store, currency: 'CNY') }
  let(:subscriber) { described_class.new }

  def event(payload)
    Struct.new(:name, :payload).new('order.submitted', payload)
  end

  it 'locks a snapshot when the store has a rate for the order currency' do
    create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY', rate: BigDecimal('7.1'))

    expect { subscriber.handle(event({ 'order_id' => order.prefixed_id })) }
      .to change(PallasTrade::FxSnapshot, :count).by(1)

    snapshot = PallasTrade::FxSnapshot.last
    expect(snapshot.order_id).to eq(order.id)
    expect(snapshot.effective_rate.to_d).to eq(BigDecimal('7.1'))
  end

  it 'accepts the nested and raw payload shapes the cart publishes' do
    create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY', rate: BigDecimal('7.1'))

    subscriber.handle(event({ 'payload' => { 'order_id' => order.prefixed_id } }))
    expect(PallasTrade::FxSnapshot.count).to eq(1)
    expect(PallasTrade::FxSnapshot.last.occurrences).to eq(1)

    other_order = create(:order, store: store, currency: 'CNY')
    subscriber.handle(event({ 'id' => other_order.id }))
    expect(PallasTrade::FxSnapshot.where(order_id: other_order.id).count).to eq(1)
  end

  it 'writes nothing when the order currency already is the settlement currency' do
    usd_order = create(:order, store: store, currency: 'USD')

    expect { subscriber.handle(event({ 'order_id' => usd_order.prefixed_id })) }
      .not_to change(PallasTrade::FxSnapshot, :count)
  end

  it 'writes nothing when no rate is configured (never guesses)' do
    expect { subscriber.handle(event({ 'order_id' => order.prefixed_id })) }
      .not_to change(PallasTrade::FxSnapshot, :count)
  end

  it 'never blocks the order flow when the lock raises' do
    allow(PallasTrade::Order).to receive(:find_by_param).and_raise(StandardError, 'boom')
    allow(Rails.logger).to receive(:error)

    expect { subscriber.handle(event({ 'order_id' => order.prefixed_id })) }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with(/lock failed/)
  end

  it 'ignores an unknown order' do
    expect { subscriber.handle(event({ 'order_id' => 'or_does_not_exist' })) }
      .not_to change(PallasTrade::FxSnapshot, :count)
  end
end
