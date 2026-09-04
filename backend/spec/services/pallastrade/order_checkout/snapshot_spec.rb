# frozen_string_literal: true

require 'rails_helper'

# CHK-P1-3 (PRD §12)：OrderCheckout::Snapshot —— 确定性 transaction projection（只读）。
RSpec.describe PallasTrade::OrderCheckout::Snapshot, type: :model do
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }
  let(:user) { create(:user) }

  def quoted_order
    order = create(:order_with_line_items, store: store, user: user,
                                           line_items_price: 100, shipment_cost: 5)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         completed_at: nil, payment_state: 'balance_due', payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    PallasTrade::OrderCheckout::Recalculate.call(order: order.reload)
    order.reload
  end

  describe '.call' do
    it 'returns nil for a nil order' do
      expect(described_class.call(order: nil)).to be_nil
    end

    context 'quoted standard order (AC-302)' do
      subject(:snapshot) { described_class.call(order: order) }

      let(:order) { quoted_order }

      it 'projects order identity + quote version fields' do
        expect(snapshot.order_id).to eq(order.prefixed_id)
        expect(snapshot.number).to eq(order.number)
        expect(snapshot.state).to eq('pending')
        expect(snapshot.currency).to eq('USD')
        expect(snapshot.checkout_version).to eq(order.checkout_version)
        expect(snapshot.price_version).to eq(order.price_version)
        expect(snapshot.checkout_expires_at).to eq(order.checkout_expires_at&.iso8601)
      end

      it 'projects authoritative money fields as decimal strings' do
        expect(snapshot.item_total).to eq(order.item_total.to_s)
        expect(snapshot.shipment_total).to eq(order.shipment_total.to_s)
        expect(snapshot.total).to eq(order.total.to_s)
        expect(snapshot.amount_due).to eq(order.amount_due.to_s)
      end

      it 'is deterministic for an unchanged order (same fingerprint)' do
        first = described_class.call(order: order)
        second = described_class.call(order: order.reload)

        expect(second.fingerprint).to eq(first.fingerprint)
        expect(second.to_h).to eq(first.to_h)
      end

      it 'changes fingerprint when price_version/amount changes' do
        before = described_class.call(order: order).fingerprint

        PallasTrade::OrderCheckout::Recalculate.call(order: order.reload)

        after = described_class.call(order: order.reload).fingerprint
        expect(after).not_to eq(before)
      end

      it 'is read-only — never mutates the order' do
        version_before = order.checkout_version
        expires_before = order.checkout_expires_at

        described_class.call(order: order)

        expect(order.reload.checkout_version).to eq(version_before)
        expect(order.reload.checkout_expires_at).to eq(expires_before)
      end
    end
  end
end
