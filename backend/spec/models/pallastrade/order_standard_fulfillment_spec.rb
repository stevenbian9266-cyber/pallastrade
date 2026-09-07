# frozen_string_literal: true

require 'rails_helper'

# REQ-20260907-order-standard-fulfillment-and-storefront-visibility
# 标准流程（正向链路）履约打通：
#   - paid/processing 订单具备履约条件（Order#can_ship? / Shipment#determine_state → ready）
#   - 发货后推进标准状态机（advance_standard_fulfillment!：部分→processing / 全部→shipped）
#   - 派生刷新 refresh_fulfillment_states!（幂等，治愈存量卡 pending）
#   - legacy 行为零回归
RSpec.describe PallasTrade::Order, type: :model do
  let(:store) { create(:store, code: "std_fulfill_#{SecureRandom.hex(4)}") }

  def paid_standard_order
    create(:order, store: store, state: 'paid', status: 'placed',
                   submitted_at: Time.current, completed_at: Time.current,
                   payment_state: 'paid', currency: store.default_currency,
                   email: 'buyer@example.com')
  end

  def attach_shipment(order, state: 'pending')
    shipment = PallasTrade::Shipment.create!(
      order: order,
      stock_location: create(:stock_location),
      state: state
    )
    order.shipments.reload
    shipment
  end

  describe 'Order#can_ship?（标准流程履约闸门）' do
    it 'returns true for standard-flow paid / processing orders' do
      paid = paid_standard_order
      expect(paid.can_ship?).to be(true)

      paid.update_column(:state, 'processing')
      expect(paid.can_ship?).to be(true)
    end

    it 'returns false while a standard-flow order is still pending (unpaid)' do
      order = paid_standard_order
      order.update_columns(state: 'pending', completed_at: nil)
      expect(order.can_ship?).to be(false)
    end

    it 'keeps legacy semantics: complete orders stay shippable' do
      legacy = create(:order, store: store, state: 'complete', status: 'placed',
                              completed_at: Time.current, email: 'buyer@example.com')
      expect(legacy.can_ship?).to be(true)
    end
  end

  describe 'Shipment 就绪（determine_state → ready）' do
    it 'makes a pending shipment ready once a standard order is paid' do
      order = paid_standard_order
      shipment = attach_shipment(order, state: 'pending')

      expect(shipment.determine_state(order)).to eq('ready')
    end

    it 'stays pending while the standard order is unpaid' do
      order = paid_standard_order
      order.update_columns(state: 'pending', completed_at: nil)
      shipment = attach_shipment(order, state: 'pending')

      expect(shipment.determine_state(order)).to eq('pending')
    end
  end

  describe '#refresh_fulfillment_states!' do
    it 'recomputes pending → ready and refreshes order shipment_state (heals stuck orders)' do
      order = paid_standard_order
      shipment = attach_shipment(order, state: 'pending')

      order.refresh_fulfillment_states!

      expect(shipment.reload.state).to eq('ready')
      expect(order.reload.shipment_state).to eq('ready')
    end

    it 'never downgrades an already shipped shipment' do
      order = paid_standard_order
      shipment = attach_shipment(order, state: 'shipped')
      shipment.update_column(:shipped_at, Time.current)

      order.refresh_fulfillment_states!

      expect(shipment.reload.state).to eq('shipped')
    end

    it 'is a no-op for non-standard (legacy) orders' do
      legacy = create(:order, store: store, state: 'complete', status: 'placed',
                              completed_at: Time.current, email: 'buyer@example.com')
      attach_shipment(legacy, state: 'pending')

      expect { legacy.refresh_fulfillment_states! }.not_to change { legacy.shipments.first.state }
    end
  end

  describe '#advance_standard_fulfillment!（发货后推进标准状态机）' do
    it 'moves a fully-shipped single-shipment paid order to shipped' do
      order = paid_standard_order
      shipment = attach_shipment(order, state: 'ready')

      expect { shipment.ship }.to change { order.reload.state }.from('paid').to('shipped')
      expect(shipment.reload.state).to eq('shipped')
      expect(order.reload.shipment_state).to eq('shipped')
    end

    it 'moves to processing on partial shipment, then shipped once all shipped' do
      order = paid_standard_order
      first = attach_shipment(order, state: 'ready')
      second = attach_shipment(order, state: 'ready')

      first.ship
      expect(order.reload.state).to eq('processing')
      expect(order.reload.shipment_state).to eq('partial')

      second.ship
      expect(order.reload.state).to eq('shipped')
      expect(order.reload.shipment_state).to eq('shipped')
    end

    it 'is a no-op for legacy checkout orders (zero regression)' do
      legacy = create(:order, store: store, state: 'complete', status: 'placed',
                              completed_at: Time.current, email: 'buyer@example.com')
      shipment = attach_shipment(legacy, state: 'ready')

      expect { shipment.ship }.not_to(change { legacy.reload.state })
    end
  end

  describe 'PallasTrade::Shipments::Update（标准流程派生刷新）' do
    it 'derives ready + order shipment_state after saving tracking on a paid standard order' do
      order = paid_standard_order
      shipment = attach_shipment(order, state: 'pending')

      result = PallasTrade::Shipments::Update.call(
        shipment: shipment,
        shipment_attributes: { tracking: 'TRK-123' }
      )

      expect(result).to be_success
      expect(shipment.reload.state).to eq('ready')
      expect(order.reload.shipment_state).to eq('ready')
    end
  end
end
