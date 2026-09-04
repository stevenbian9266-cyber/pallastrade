# frozen_string_literal: true

# PRD-20260904-api-txn-p2-2 AC-201/202/203/204/205
require 'rails_helper'

RSpec.describe PallasTrade::Transactions::Start, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(
      :order,
      store: store,
      state: 'pending',
      status: 'placed',
      submitted_at: Time.current,
      item_total: 10,
      total: 10,
      payment_state: 'balance_due',
      currency: store.default_currency
    )
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }

  def start(**opts)
    described_class.call(order: order, payment_method: payment_method, **opts)
  end

  describe '#call' do
    it 'AC-201 creates transaction + frozen snapshot + primary participant + attaches session' do
      result = start
      expect(result).to be_success

      tx = result.value[:transaction]
      expect(tx).to be_a(PallasTrade::CommerceTransaction)
      expect(tx.state).to eq('payment_pending')
      expect(tx.purpose).to eq('purchase')
      expect(tx.amount.to_f).to eq(10.0)
      expect(tx.snapshot_frozen?).to be true
      expect(tx.snapshot_fingerprint).to be_present

      expect(tx.transaction_orders.count).to eq(1)
      expect(tx.transaction_orders.first.role).to eq('primary')
      expect(tx.transaction_orders.first.order_id).to eq(order.id)

      session = result.value[:payment_session]
      expect(session.persisted?).to be true
      expect(session.transaction_id).to eq(tx.id)
      expect(order.payment_sessions.count).to eq(1)
    end

    it 'AC-202 replays return the same active transaction and reused session' do
      first = start
      second = start

      expect(second).to be_success
      expect(second.value[:transaction].id).to eq(first.value[:transaction].id)
      expect(second.value[:payment_session].id).to eq(first.value[:payment_session].id)
      expect(order.payment_sessions.count).to eq(1)
      expect(PallasTrade::TransactionOrder.where(order: order).count).to eq(1)
    end

    it 'AC-203 refuses a new payment while a terminal transaction exists' do
      tx = start.value[:transaction]
      tx.confirm_payment! # payment_confirmed → Payment Start Policy 禁止新 attempt

      result = start
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('transaction_not_payable')
    end

    it 'AC-205 returns checkout_not_ready when a quote-active order lacks contact' do
      quote_order = create(
        :order,
        store: store,
        state: 'pending',
        status: 'placed',
        email: nil,
        submitted_at: Time.current,
        item_total: 10,
        total: 10,
        payment_state: 'balance_due',
        checkout_expires_at: Time.current + 1.hour,
        checkout_version: 0,
        currency: store.default_currency
      )
      result = described_class.call(order: quote_order, payment_method: payment_method)
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('checkout_not_ready')
    end
  end

  describe 'quote consent (AC-204)' do
    let(:address) { create(:address) }
    # quote-active 标准订单：readiness 齐备（email/address/shipments selected rate）+ 过期
    let(:quote_order) do
      o = create(
        :order_with_line_items,
        store: store,
        email: 'buyer@example.com',
        ship_address: address,
        shipment_cost: 0,
        line_items_price: 10
      )
      o.shipments.each do |shipment|
        shipment.shipping_rates.destroy_all
        shipment.add_shipping_method(create(:free_shipping_method), true)
      end
      o.update_columns(
        state: 'pending', status: 'placed', submitted_at: Time.current,
        checkout_expires_at: 5.minutes.ago, checkout_version: 1, price_version: 'pv-1',
        payment_state: 'balance_due'
      )
      o.line_items.reload
      o
    end

    it 'transparent refresh continues when commercial facts are unchanged' do
      result = described_class.call(order: quote_order, payment_method: payment_method)
      expect(result).to be_success
      expect(result.value[:transaction].amount.to_f).to be > 0
    end

    it 'returns quote_changed when refresh changes the authoritative amount (INV-07)' do
      o = create(
        :order_with_line_items,
        store: store,
        email: 'buyer@example.com',
        ship_address: address,
        shipment_cost: 0,
        line_items_price: 20 # 行项目权威合计 20
      )
      o.shipments.each do |shipment|
        shipment.shipping_rates.destroy_all
        shipment.add_shipping_method(create(:free_shipping_method), true)
      end
      # 人为把 total/price_version 调低，使 Recalculate 后权威金额上升 → 商业事实变化
      o.update_columns(
        state: 'pending', status: 'placed', submitted_at: Time.current,
        total: 10.0, item_total: 10.0, payment_total: 0,
        checkout_expires_at: 5.minutes.ago, checkout_version: 1, price_version: 'pv-stale',
        payment_state: 'balance_due'
      )
      o.line_items.reload

      result = described_class.call(order: o, payment_method: payment_method)
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('quote_changed')
      expect(result.error.value[:latest][:amount_due].to_f).to be >= 20
      expect(o.reload.payment_sessions.count).to eq(0)
      expect(PallasTrade::CommerceTransaction.where(store: store).count).to eq(0)
    end
  end
end
