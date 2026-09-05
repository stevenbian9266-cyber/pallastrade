# frozen_string_literal: true

require 'rails_helper'

# INV-P3-5 (PRD-20260905-shipping-...)
# InventoryFactResolver —— 库存事实矩阵（FR-041/042，AC-3027）。
RSpec.describe PallasTrade::Transactions::InventoryFactResolver, type: :service do
  let(:store) { create(:store, code: 'invfact_store') }
  let(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }

  def build_variant
    v = create(:product, store: store).master
    v.update_column(:track_inventory, true)
    si = create(:stock_item, variant: v, stock_location: stock_location)
    si.update_columns(count_on_hand: 5, backorderable: false)
    v
  end

  def build_order(variant)
    o = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                       item_total: 10, total: 10, payment_state: 'balance_due',
                       currency: store.default_currency, email: 'x@example.com')
    create(:line_item, order: o, variant: variant, quantity: 1, price: 10)
    o.line_items.reload
    o
  end

  def build_transaction(order)
    tx = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase',
                                                  currency: order.currency, amount: order.amount_due)
    PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order, role: 'primary',
                                          amount_snapshot: order.amount_due)
    tx
  end

  it 'NOT_REQUIRED when no participant requires inventory' do
    tx = build_transaction(build_order(build_variant))
    # 让该 line item 变为不 track 库存
    tx.transaction_orders.first.order.line_items.first.variant.update_column(:track_inventory, false)

    result = described_class.call(transaction: tx)

    expect(result).to be_success
    expect(result.value[:verdict]).to eq(:not_required)
  end

  it 'RESERVED when required demand is covered by active reserved rows' do
    variant = build_variant
    order = build_order(variant)
    tx = build_transaction(order)
    create(:stock_reservation, order: order, line_item: order.line_items.first,
                               stock_item: variant.stock_items.first, quantity: 1)

    result = described_class.call(transaction: tx)

    expect(result.value[:verdict]).to eq(:reserved)
  end

  it 'COMMITTED when covered by committed rows and order completed' do
    variant = build_variant
    order = build_order(variant)
    tx = build_transaction(order)
    create(:stock_reservation, order: order, line_item: order.line_items.first,
                               stock_item: variant.stock_items.first, quantity: 1)
    order.line_items.first.stock_reservations.first.commit!
    order.update_columns(completed_at: Time.current, state: 'paid')

    result = described_class.call(transaction: tx)

    expect(result.value[:verdict]).to eq(:committed)
  end

  it 'RELEASED when released without coverage' do
    variant = build_variant
    order = build_order(variant)
    tx = build_transaction(order)
    row = create(:stock_reservation, order: order, line_item: order.line_items.first,
                                     stock_item: variant.stock_items.first, quantity: 1)
    row.update!(release_reason: 'test')
    row.release!

    result = described_class.call(transaction: tx)

    expect(result.value[:verdict]).to eq(:released)
  end

  it 'EXPIRED when expired without coverage' do
    variant = build_variant
    order = build_order(variant)
    tx = build_transaction(order)
    row = create(:stock_reservation, order: order, line_item: order.line_items.first,
                                     stock_item: variant.stock_items.first, quantity: 1)
    row.update_column(:expires_at, 1.minute.ago)
    row.expire!

    result = described_class.call(transaction: tx)

    expect(result.value[:verdict]).to eq(:expired)
  end

  it 'UNRESERVED when required demand has no reservation rows' do
    tx = build_transaction(build_order(build_variant))
    result = described_class.call(transaction: tx)

    expect(result.value[:verdict]).to eq(:unreserved)
  end

  it 'AMBIGUOUS when PARTIAL (one item committed, another still reserved)' do
    variant_a = build_variant
    variant_b = build_variant
    order = build_order(variant_a)
    create(:line_item, order: order, variant: variant_b, quantity: 1, price: 10)
    order.line_items.reload
    tx = build_transaction(order)
    create(:stock_reservation, order: order, line_item: order.line_items[0],
                               stock_item: variant_a.stock_items.first, quantity: 1)
    row_b = create(:stock_reservation, order: order, line_item: order.line_items[1],
                                       stock_item: variant_b.stock_items.first, quantity: 1)
    row_b.commit!

    result = described_class.call(transaction: tx)

    expect(result.value[:verdict]).to eq(:ambiguous)
  end
end
