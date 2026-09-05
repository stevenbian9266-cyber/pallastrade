# frozen_string_literal: true

require 'rails_helper'

# INV-P3-1 (PRD-20260905-shipping-...)：
# Release —— RESERVED → RELEASED（不再硬删除）；幂等；只处理 reserved 行。
RSpec.describe PallasTrade::StockReservations::Release, type: :service do
  let!(:store) { create(:store, code: 'res_release_store') }
  let!(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variant_a) { create(:product, store: store).master }
  let(:variant_b) { create(:product, store: store).master }
  let(:stock_item_a) { create(:stock_item, variant: variant_a, stock_location: stock_location) }
  let(:stock_item_b) { create(:stock_item, variant: variant_b, stock_location: stock_location) }
  let!(:order) do
    create(:order_with_line_items, store: store, line_items_count: 2, line_items_price: 10,
                                   variants: [variant_a, variant_b])
  end
  let(:line_items) { order.line_items.reload.to_a }

  before do
    [variant_a, variant_b].each { |v| v.update_column(:track_inventory, true) }
    [stock_item_a, stock_item_b].each { |si| si.update_columns(count_on_hand: 5, backorderable: false) }
  end

  it 'transitions RESERVED rows of the order to RELEASED with reason (not deleted)' do
    r1 = create(:stock_reservation, order: order, line_item: line_items[0], stock_item: stock_item_a, quantity: 1)
    result = described_class.call(order: order, reason: 'test_release')

    expect(result.success?).to be true
    expect(r1.reload.state).to eq('released')
    expect(r1.reload.release_reason).to eq('test_release')
    expect(r1.reload.released_at).to be_present
    expect(PallasTrade::StockReservation.where(order: order).count).to eq(1) # 保留历史行
  end

  it 'is idempotent: second run does not change terminal rows' do
    r1 = create(:stock_reservation, order: order, line_item: line_items[0], stock_item: stock_item_a, quantity: 1)
    2.times { described_class.call(order: order, reason: 'x') }

    expect(r1.reload.state).to eq('released')
    expect(PallasTrade::StockReservation.released.where(order: order).count).to eq(1)
  end

  it 'releases only reserved rows; committed rows are untouched' do
    committed = create(:stock_reservation, order: order, line_item: line_items[1], stock_item: stock_item_b, quantity: 1)
    committed.commit!

    described_class.call(order: order, reason: 'test')

    expect(committed.reload.state).to eq('committed')
    expect(PallasTrade::StockReservation.reserved.where(order: order).count).to eq(0)
  end
end
