# frozen_string_literal: true

# PRD-20260823-checkout-多订单拆分与合并支付 AC-002
require 'rails_helper'

RSpec.describe PallasTrade::PaymentGroups::Create, type: :service do
  let(:store) { create(:store, code: 'pg_create_test') }
  let(:user) { create(:user) }

  def unpaid_order(currency: 'USD')
    create(:order_with_totals, store: store, user: user, currency: currency, status: 'placed',
                               payment_state: 'balance_due', completed_at: nil)
  end

  describe '#call' do
    it 'creates a payment group from multiple unpaid order ids' do
      o1 = unpaid_order
      o2 = unpaid_order

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_success
      group = result.value
      expect(group.prefixed_id).to start_with('pg_')
      expect(group.orders).to match_array([o1, o2])
      expect(group.currency).to eq('USD')
      expect(group.amount).to eq(o1.total + o2.total)
    end

    it 'rejects mixed currencies' do
      o1 = unpaid_order(currency: 'USD')
      o2 = unpaid_order(currency: 'EUR')

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_failure
      expect(result.error.value).to eq(:mixed_currency)
    end

    it 'rejects orders not owned by the user' do
      o1 = unpaid_order
      other = create(:user)
      o2 = unpaid_order
      o2.update_column(:user_id, other.id)

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_failure
      expect(result.error.value).to eq(:orders_not_owned)
    end

    it 'rejects already-paid orders' do
      o1 = unpaid_order
      o2 = unpaid_order
      o2.update_columns(payment_state: 'paid', payment_total: o2.total)

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_failure
      expect(result.error.value).to eq(:order_already_paid)
    end

    it 'rejects canceled orders' do
      o1 = unpaid_order
      o2 = unpaid_order
      o2.update_column(:status, 'canceled')

      result = described_class.call(store: store, order_ids: [o1.prefixed_id, o2.prefixed_id], user: user)

      expect(result).to be_failure
      expect(result.error.value).to eq(:order_canceled)
    end

    it 'rejects unknown order ids' do
      result = described_class.call(store: store, order_ids: ['or_does_not_exist'], user: user)
      expect(result).to be_failure
      expect(result.error.value).to eq(:orders_not_found)
    end
  end
end
