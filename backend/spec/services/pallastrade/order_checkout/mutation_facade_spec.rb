# frozen_string_literal: true

require 'rails_helper'

# CHK-P1-1B (PRD §12)：Order Checkout Mutation Facade —— 只 WRAP 既有服务并返回 CheckoutView。
RSpec.describe 'PallasTrade::OrderCheckout mutation facade', type: :model do
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }
  let(:user) { create(:user) }

  def pending_order(store:, user:)
    order = create(:order_with_line_items, store: store, user: user,
                                           line_items_price: 100, shipment_cost: 0)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         completed_at: nil, payment_state: 'balance_due', payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def extra_rate(shipment, cost:)
    create(:shipping_rate, shipment: shipment, shipping_method: create(:shipping_method), cost: BigDecimal(cost.to_s))
  end

  describe PallasTrade::OrderCheckout::UpdateContact do
    it 'updates email and returns the latest CheckoutView' do
      order = pending_order(store: store, user: user)

      result = described_class.call(order: order, email: 'new@example.com')

      expect(result.success?).to be true
      view = result.value
      expect(view).to be_a(PallasTrade::OrderCheckout::CheckoutView)
      expect(view.email).to eq('new@example.com')
      expect(order.reload.email).to eq('new@example.com')
    end

    it 'refuses completed orders' do
      order = pending_order(store: store, user: user)
      order.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)

      result = described_class.call(order: order, email: 'x@example.com')

      expect(result.success?).to be false
      expect(order.reload.email).not_to eq('x@example.com')
    end
  end

  describe PallasTrade::OrderCheckout::UpdateAddress do
    it 'updates shipping address and returns the latest CheckoutView' do
      order = pending_order(store: store, user: user)

      result = described_class.call(
        order: order,
        params: { shipping_address: { first_name: 'NewFirst', last_name: 'NewLast' } }
      )

      expect(result.success?).to be true
      view = result.value
      expect(view.shipping_address.firstname).to eq('NewFirst')
      expect(order.reload.ship_address.firstname).to eq('NewFirst')
    end

    it 'refuses completed orders' do
      order = pending_order(store: store, user: user)
      order.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)

      result = described_class.call(
        order: order,
        params: { shipping_address: { first_name: 'X' } }
      )

      expect(result.success?).to be false
      expect(order.reload.ship_address.firstname).not_to eq('X')
    end
  end

  describe PallasTrade::OrderCheckout::SelectShipping do
    it 'switches the selected delivery rate and recomputes totals via Shipments::Update' do
      order = pending_order(store: store, user: user)
      shipment = order.shipments.first
      expect(shipment).to be_present
      rate2 = extra_rate(shipment, cost: 20)
      before_total = order.amount_due

      result = described_class.call(order: order, delivery_rate_id: rate2.prefixed_id)

      expect(result.success?).to be true
      view = result.value
      expect(shipment.reload.selected_shipping_rate&.id).to eq(rate2.id)
      expect(order.reload.amount_due).to eq(before_total + BigDecimal('20'))
      expect(view.delivery_total).to eq(order.shipment_total)
    end

    it 'refuses a rate that does not belong to the order shipment' do
      order = pending_order(store: store, user: user)
      other_order = pending_order(store: store, user: user)
      foreign_rate = extra_rate(other_order.shipments.first, cost: 5)

      result = described_class.call(order: order, delivery_rate_id: foreign_rate.prefixed_id)

      expect(result.success?).to be false
    end

    it 'refuses completed orders' do
      order = pending_order(store: store, user: user)
      rate = order.shipments.first.shipping_rates.first
      order.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)

      result = described_class.call(order: order, delivery_rate_id: rate.prefixed_id)

      expect(result.success?).to be false
    end
  end
end
