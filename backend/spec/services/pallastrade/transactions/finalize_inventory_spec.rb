# frozen_string_literal: true

require 'rails_helper'

# INV-P3-3 (PRD-20260905-shipping-...)：
# Transactions::Finalize 的 inventory commit 兜底（FR-026/AC-3011/3013/3015）：
# physical consumption 成功后交易级 RESERVED→COMMITTED；失败路径不 commit、保留 RESERVED、
# Transaction → recovery_required。
RSpec.describe PallasTrade::Transactions::Finalize, type: :service do
  let(:store) { create(:store, code: 'fin_inv_store') }
  let(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variant) { create(:product, store: store).master }
  let(:stock_item) { create(:stock_item, variant: variant, stock_location: stock_location) }

  def build_order
    o = create(:order_with_line_items, store: store, variants: [variant],
                                       line_items_price: 10, shipment_cost: 0)
    o.shipments.each do |shipment|
      shipment.shipping_rates.destroy_all
      shipment.add_shipping_method(create(:free_shipping_method), true)
    end
    o.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                     payment_state: 'balance_due')
    o.line_items.reload
    o
  end

  def build_paid_transaction(order)
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: order.currency, amount: order.amount_due
    )
    PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order, role: 'primary',
                                          amount_snapshot: order.amount_due)
    # Start 的 Reserve 门等价物：reserve + bind
    tx
  end

  before do
    variant.update_column(:track_inventory, true)
    stock_item.update_columns(count_on_hand: 5, backorderable: false)
  end

  it 'AC-3011 commits transaction-bound RESERVED rows when physical consumption already succeeded' do
    order = build_order
    tx = build_paid_transaction(order)
    # 模拟 Start 已 reserve（RESERVED 且绑定 tx）
    expect(PallasTrade::Transactions::ReserveInventory.call(transaction: tx)).to be_success
    row = PallasTrade::StockReservation.reserved.where(order: order).first
    expect(row.state).to eq('reserved')

    # 模拟物理消费已完成（participant order completed）但 reservation 尚未 commit
    order.update_columns(completed_at: Time.current, state: 'paid', status: 'placed')

    tx.start_payment!
    tx.confirm_payment! # → payment_confirmed，Finalize 可执行
    result = described_class.call(transaction: tx)

    expect(result).to be_success
    expect(tx.reload.state).to eq('completed')
    expect(row.reload.state).to eq('committed')
    expect(row.reload.committed_at).to be_present
    expect(stock_item.reload.count_on_hand).to eq(5) # commit 不产生第二套扣减
  end

  it 'AC-3013 leaves reservations RESERVED and flags recovery_required when participant finalization fails' do
    order = build_order
    tx = build_paid_transaction(order)
    expect(PallasTrade::Transactions::ReserveInventory.call(transaction: tx)).to be_success
    row = PallasTrade::StockReservation.reserved.where(order: order).first

    tx.start_payment!
    tx.confirm_payment!
    # 无本地 payment / payment split → standard 订单无法完成 → member complete 失败
    result = described_class.call(transaction: tx)

    expect(result).to be_failure
    expect(tx.reload.state).to eq('recovery_required')
    expect(row.reload.state).to eq('reserved')
  end
end
