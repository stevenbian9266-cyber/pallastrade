# frozen_string_literal: true

require 'rails_helper'

# CHK-P1-2 (PRD §12)：Version / Price Version / Expiration / Recalculate / Refresh。
RSpec.describe 'PallasTrade::OrderCheckout versioning (P1-2)', type: :model do
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

  describe PallasTrade::OrderCheckout::Recalculate do
    it 'computes and persists a price_version and initializes checkout_expires_at' do
      order = pending_order(store: store, user: user)
      expect(order.price_version).to be_nil
      expect(order.checkout_expires_at).to be_nil

      result = described_class.call(order: order)

      expect(result.success?).to be true
      refreshed = result.value
      expect(refreshed.price_version).to be_present
      expect(refreshed.price_version).to match(/\A[0-9a-f]{16}\z/)
      expect(refreshed.checkout_expires_at).to be > Time.current
    end

    it 'is deterministic for unchanged money input (same fingerprint)' do
      order = pending_order(store: store, user: user)
      first = described_class.call(order: order).value.price_version
      second = described_class.call(order: order.reload).value.price_version

      expect(second).to eq(first)
    end

    it 'changes price_version when authoritative money input changes' do
      order = pending_order(store: store, user: user)
      before = described_class.call(order: order).value.price_version

      order.line_items.first.update!(price: 150)
      PallasTrade::OrderUpdater.new(order).update
      after = described_class.call(order: order.reload).value.price_version

      expect(after).not_to eq(before)
    end

    it 'increments checkout_version on each recalculate' do
      order = pending_order(store: store, user: user)
      before_version = order.checkout_version

      described_class.call(order: order)

      expect(order.reload.checkout_version).to eq(before_version + 1)
    end
  end

  describe PallasTrade::OrderCheckout::Refresh do
    it 'recalculates, renews expiration and returns the latest CheckoutView' do
      order = pending_order(store: store, user: user)
      described_class.call(order: order) # init
      order.update_columns(checkout_expires_at: 1.hour.ago)

      result = described_class.call(order: order)

      expect(result.success?).to be true
      view = result.value
      expect(view).to be_a(PallasTrade::OrderCheckout::CheckoutView)
      expect(order.reload.checkout_expires_at).to be > Time.current
      expect(view.price_version).to be_present
    end

    it 'refuses completed orders' do
      order = pending_order(store: store, user: user)
      order.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)

      result = described_class.call(order: order)

      expect(result.success?).to be false
    end
  end

  describe PallasTrade::OrderCheckout::Expiration do
    let(:service) { described_class.new }

    it 'is not expired when expires_at is nil (legacy default)' do
      order = pending_order(store: store, user: user)
      expect(service.expired?(order: order)).to be false
    end

    it 'is expired when checkout_expires_at is in the past' do
      order = pending_order(store: store, user: user)
      order.update_columns(checkout_expires_at: 5.minutes.ago)

      expect(service.expired?(order: order)).to be true
    end

    it 'returns positive expires_in for a valid quote' do
      order = pending_order(store: store, user: user)
      order.update_columns(checkout_expires_at: 10.minutes.from_now)

      expect(service.expires_in(order: order)).to be > 0
    end
  end

  describe 'Checkout Version (checkout_version column)' do
    it 'increments checkout_version after an address mutation (which recalcs)' do
      order = pending_order(store: store, user: user)
      before_version = order.checkout_version

      PallasTrade::OrderCheckout::UpdateAddress.call(
        order: order,
        params: { shipping_address: { first_name: 'Concurrent' } }
      )

      expect(order.reload.checkout_version).to be > before_version
    end

    it 'increments checkout_version after a contact mutation (no recalc, manual bump)' do
      order = pending_order(store: store, user: user)
      before_version = order.checkout_version

      PallasTrade::OrderCheckout::UpdateContact.call(order: order, email: 'v@example.com')

      expect(order.reload.checkout_version).to eq(before_version + 1)
    end
  end
end
