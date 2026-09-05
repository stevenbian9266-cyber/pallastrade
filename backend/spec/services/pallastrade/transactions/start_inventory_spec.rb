# frozen_string_literal: true

require 'rails_helper'

# INV-P3-2 (PRD-20260905-shipping-...) 真实链路集成：
# Transactions::Start → Snapshot V2（inventory demand evidence）→ ReserveInventory
# → PaymentSessions::Start（AC-3001/3002/3007/3008）。
RSpec.describe PallasTrade::Transactions::Start, type: :service do
  let(:store) { create(:store, code: 'start_inv_store') }
  let(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variant) { create(:product, store: store).master }
  let(:stock_item) { create(:stock_item, variant: variant, stock_location: stock_location) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }

  let(:order) do
    o = create(:order_with_line_items, store: store, variants: [variant],
                                       line_items_price: 10, shipment_cost: 0)
    o.shipments.each do |shipment|
      shipment.shipping_rates.destroy_all
      shipment.add_shipping_method(create(:free_shipping_method), true)
    end
    o.update_columns(
      state: 'pending', status: 'placed', submitted_at: Time.current,
      payment_state: 'balance_due', checkout_expires_at: nil
    )
    o.line_items.reload
    o
  end

  before do
    variant.update_column(:track_inventory, true)
    stock_item.update_columns(count_on_hand: 5, backorderable: false)
  end

  it 'AC-3001/AC-3007 reserves before PaymentSession with Snapshot V2 demand evidence' do
    result = described_class.call(order: order, payment_method: payment_method)

    expect(result).to be_success
    tx = result.value[:transaction]
    expect(tx.state).to eq('payment_pending')
    expect(tx.snapshot_schema_version).to eq(PallasTrade::CommerceTransaction::CURRENT_SNAPSHOT_SCHEMA_VERSION)
    expect(tx.snapshot_data['schema_version']).to eq(2)
    demand = tx.snapshot_data.dig('participant_orders', 0, 'inventory_demand')
    expect(demand).to be_present
    expect(demand.first['stock_requirement']).to eq('REQUIRED')
    expect(demand.first['quantity']).to eq(order.line_items.first.quantity)

    rows = PallasTrade::StockReservation.reserved.where(order: order)
    expect(rows.count).to eq(1)
    expect(rows.first.commerce_transaction_id).to eq(tx.id)

    session = result.value[:payment_session]
    expect(session).to be_present
    expect(session.transaction_id).to eq(tx.id)
  end

  it 'AC-3002 refuses payment when a REQUIRED item cannot be reserved (no session/PSP side effect)' do
    stock_item.update_column(:count_on_hand, 0)

    result = described_class.call(order: order, payment_method: payment_method)

    expect(result).to be_failure
    error = result.error
    value = error.respond_to?(:value) ? error.value : nil
    expect(value.is_a?(Hash) ? value[:code] : value).to eq('INSUFFICIENT_STOCK')
    expect(order.payment_sessions.count).to eq(0)
    tx = PallasTrade::CommerceTransaction.active_for_order(order, purpose: 'purchase')
    expect(tx).to be_present
    expect(tx.state).to eq('created') # 前支付状态，可安全 Resume/取消
  end
end
