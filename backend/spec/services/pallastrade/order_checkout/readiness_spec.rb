# frozen_string_literal: true

require 'rails_helper'

# CHK-P1-3 (PRD §12)：OrderCheckout::Readiness —— 只读聚合（不复制校验规则）。
RSpec.describe PallasTrade::OrderCheckout::Readiness, type: :model do
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }
  let(:user) { create(:user) }

  def ready_order
    order = create(:order_with_line_items, store: store, user: user,
                                           line_items_price: 100, shipment_cost: 5)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         completed_at: nil, payment_state: 'balance_due', payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  describe '.call' do
    it 'returns a non-ready empty result for a nil order' do
      result = described_class.call(order: nil)

      expect(result.ready).to be false
      expect(result.missing_requirements).to eq([])
    end

    context 'canonical pending order (AC-301)' do
      subject(:result) { described_class.call(order: order) }

      let(:order) { ready_order }

      it 'reports ready when email/address/delivery/balance are all present' do
        expect(result.ready).to be true
        expect(result.missing_requirements).to eq([])
      end

      it 'flags missing contact when email is blank' do
        order.update_columns(email: nil)

        expect(result.ready).to be false
        expect(result.missing_requirements).to include('contact')
      end

      it 'flags missing shipping_address when a physical order has no ship address' do
        order.update_columns(ship_address_id: nil)

        expect(result.ready).to be false
        expect(result.missing_requirements).to include('shipping_address')
      end

      it 'does not require a shipping address for digital-only orders' do
        allow(order).to receive(:requires_ship_address?).and_return(false)

        expect(result.missing_requirements).not_to include('shipping_address')
      end

      it 'flags missing delivery_rate when shipments exist but none has a selected rate' do
        order.shipments.each do |shipment|
          shipment.shipping_rates.update_all(selected: false)
          shipment.reload
        end

        expect(result.ready).to be false
        expect(result.missing_requirements).to include('delivery_rate')
      end

      it 'does not require a delivery rate when the order has no shipments' do
        order.shipments.destroy_all
        order.reload

        expect(result.missing_requirements).not_to include('delivery_rate')
      end

      it 'flags missing balance when amount_due is not positive' do
        order.update_columns(payment_total: order.total)

        expect(result.ready).to be false
        expect(result.missing_requirements).to include('balance')
      end
    end
  end
end
