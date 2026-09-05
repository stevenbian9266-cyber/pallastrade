# frozen_string_literal: true

require 'rails_helper'

# INV-P3-2 (PRD-20260905-shipping-...)
# Transactions::ReserveInventory —— Start 的 Reserve 门（AC-3001/3002/3003/3004/3005）。
RSpec.describe PallasTrade::Transactions::ReserveInventory, type: :service do
  let(:store) { create(:store, code: 'resinv_store') }
  let(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variant) { create(:product, store: store).master }
  let(:stock_item) { create(:stock_item, variant: variant, stock_location: stock_location) }

  def build_order(variant:, quantity: 1, count_on_hand: 5, backorderable: false)
    o = create(:order_with_line_items, store: store, variants: [variant],
                                       line_items_price: 10, shipment_cost: 0)
    o.line_items.first.update!(quantity: quantity)
    variant.update_column(:track_inventory, true)
    si = variant.stock_items.where(stock_location: stock_location).first ||
      create(:stock_item, variant: variant, stock_location: stock_location)
    si.update_columns(count_on_hand: count_on_hand, backorderable: backorderable)
    o.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current)
    o.line_items.reload
    o
  end

  def build_transaction(order, purpose: 'purchase')
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, customer: order.user, purpose: purpose,
      currency: order.currency, amount: order.amount_due
    )
    PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order, role: 'primary', amount_snapshot: order.amount_due)
    tx
  end

  before do
    variant.update_column(:track_inventory, true)
    stock_item.update_columns(count_on_hand: 5, backorderable: false)
  end

  it 'AC-3001 reserves required inventory and binds rows to the transaction' do
    order = build_order(variant: variant, quantity: 1)
    tx = build_transaction(order)

    result = described_class.call(transaction: tx)

    expect(result).to be_success
    rows = PallasTrade::StockReservation.reserved.where(order: order)
    expect(rows.count).to eq(1)
    expect(rows.first.commerce_transaction_id).to eq(tx.id)
  end

  it 'AC-3003 is idempotent across repeated reserve calls' do
    order = build_order(variant: variant, quantity: 2)
    tx = build_transaction(order)

    2.times { expect(described_class.call(transaction: tx)).to be_success }

    rows = PallasTrade::StockReservation.reserved.where(order: order)
    expect(rows.count).to eq(1)
    expect(rows.first.quantity).to eq(2)
  end

  it 'AC-3002 fails with INSUFFICIENT_STOCK when a REQUIRED item has no on-hand stock' do
    order = build_order(variant: variant, quantity: 1, count_on_hand: 0)
    tx = build_transaction(order)

    result = described_class.call(transaction: tx)

    expect(result).to be_failure
    code = result.error.respond_to?(:value) && result.error.value.is_a?(Hash) ? result.error.value[:code] : result.error
    expect(code).to eq('INSUFFICIENT_STOCK')
  end

  it 'AC-3005 skips backorderable variants (NOT_REQUIRED) with success' do
    order = build_order(variant: variant, quantity: 1, count_on_hand: 0, backorderable: true)
    tx = build_transaction(order)

    result = described_class.call(transaction: tx)

    expect(result).to be_success
    expect(PallasTrade::StockReservation.where(order: order).count).to eq(0)
  end

  it 'FR-037 returns INVENTORY_CHANGED when an expired reservation can no longer be re-reserved' do
    order = build_order(variant: variant, quantity: 1, count_on_hand: 5)
    tx = build_transaction(order)
    expect(described_class.call(transaction: tx)).to be_success
    row = PallasTrade::StockReservation.reserved.where(order: order).first

    # 模拟 TTL 到期（ExpireJob）后库存被买走
    row.expire!
    stock_item.update_column(:count_on_hand, 0)

    result = described_class.call(transaction: tx)

    expect(result).to be_failure
    value = result.error.value
    expect(value.is_a?(Hash) ? value[:code] : value).to eq('INVENTORY_CHANGED')
  end

  describe 'combination compensation (FR-021)' do
    let(:variant_b) { create(:product, store: store).master }

    it 'releases only reservations created this attempt when a later participant fails' do
      order_a = build_order(variant: variant, quantity: 1, count_on_hand: 5)
      order_b = build_order(variant: variant_b, quantity: 2, count_on_hand: 1) # Reserve 将 raise Insufficient

      tx = PallasTrade::CommerceTransaction.create!(
        store: store, purpose: 'combined_payment', currency: order_a.currency, amount: order_a.amount_due + order_b.amount_due
      )
      PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order_a, role: 'primary', amount_snapshot: order_a.amount_due)
      PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order_b, role: 'participant', amount_snapshot: order_b.amount_due)

      result = described_class.call(transaction: tx)

      expect(result).to be_failure
      # order_a 本次新建的 RESERVED 已被补偿为 RELEASED（不留占用）
      expect(PallasTrade::StockReservation.reserved.where(order: order_a).count).to eq(0)
      expect(PallasTrade::StockReservation.released.where(order: order_a).count).to eq(1)
    end

    it 'does not release pre-existing reservations that belong to an earlier successful attempt' do
      order_a = build_order(variant: variant, quantity: 1, count_on_hand: 5)
      pre = create(:stock_reservation, order: order_a, line_item: order_a.line_items.first,
                                       stock_item: stock_item, quantity: 1, commerce_transaction_id: nil)
      order_b = build_order(variant: variant_b, quantity: 2, count_on_hand: 1)

      tx = PallasTrade::CommerceTransaction.create!(
        store: store, purpose: 'combined_payment', currency: order_a.currency, amount: order_a.amount_due + order_b.amount_due
      )
      PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order_a, role: 'primary', amount_snapshot: order_a.amount_due)
      PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order_b, role: 'participant', amount_snapshot: order_b.amount_due)

      result = described_class.call(transaction: tx)

      expect(result).to be_failure
      # pre 是本次 attempt 前已存在（before_ids）→ 不被补偿释放
      expect(pre.reload.state).to eq('reserved')
    end
  end
end
