# frozen_string_literal: true

require 'rails_helper'

# INV-P3-1/INV-P3-3 (PRD-20260905-shipping-...)：
# Commit —— physical consumption 成功后的 Reservation 事实确认（RESERVED → COMMITTED）。
# 幂等；绝不修改 count_on_hand（不产生第二套扣减，AC-3010/3011/3015）。
RSpec.describe PallasTrade::StockReservations::Commit, type: :service do
  let!(:store) { create(:store, code: 'res_commit_store') }
  let!(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variant) { create(:product, store: store).master }
  let(:stock_item) { create(:stock_item, variant: variant, stock_location: stock_location) }
  let!(:order) do
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 10,
                                   variants: [variant])
  end
  let(:line_item) { order.line_items.first }
  let!(:reservation) do
    create(:stock_reservation, order: order, line_item: line_item, stock_item: stock_item, quantity: 1)
  end

  before do
    variant.update_column(:track_inventory, true)
    stock_item.update_columns(count_on_hand: 5, backorderable: false)
  end

  it 'marks RESERVED rows of the order COMMITTED with committed_at' do
    result = described_class.call(order: order)

    expect(result.success?).to be true
    expect(reservation.reload.state).to eq('committed')
    expect(reservation.reload.committed_at).to be_present
    expect(PallasTrade::StockReservation.where(order: order).count).to eq(1) # 保留历史
  end

  it 'does not modify count_on_hand (no second physical decrement)' do
    described_class.call(order: order)

    expect(stock_item.reload.count_on_hand).to eq(5)
    expect(PallasTrade::StockMovement.where(stock_item: stock_item).count).to eq(0)
  end

  it 'is idempotent across repeated runs' do
    3.times { described_class.call(order: order) }

    expect(reservation.reload.state).to eq('committed')
    expect(PallasTrade::StockReservation.committed.where(order: order).count).to eq(1)
    expect(PallasTrade::StockReservation.reserved.where(order: order).count).to eq(0)
  end

  it 'leaves terminal rows untouched' do
    reservation.expire!
    described_class.call(order: order)

    expect(reservation.reload.state).to eq('expired')
  end
end
