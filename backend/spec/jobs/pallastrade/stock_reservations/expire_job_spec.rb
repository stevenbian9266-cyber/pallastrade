# frozen_string_literal: true

require 'rails_helper'

# INV-P3-1 (PRD-20260905-shipping-...)：
# ExpireJob —— RESERVED 且过 TTL → EXPIRED（不再硬删除）；幂等；终态行不动（AC-3018）。
RSpec.describe PallasTrade::StockReservations::ExpireJob, type: :job do
  let!(:store) { create(:store, code: 'res_expire_store') }
  let!(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variants) { Array.new(3) { create(:product, store: store).master } }
  let(:stock_items) { variants.map { |v| create(:stock_item, variant: v, stock_location: stock_location) } }
  let!(:order) do
    create(:order_with_line_items, store: store, line_items_count: 3, line_items_price: 10,
                                   variants: variants)
  end
  let(:line_items) { order.line_items.reload.to_a }

  before do
    variants.each { |v| v.update_column(:track_inventory, true) }
    stock_items.each { |si| si.update_columns(count_on_hand: 5, backorderable: false) }
  end

  def make_reservation(index, expires_at: 10.minutes.from_now)
    create(:stock_reservation, order: order, line_item: line_items[index],
                               stock_item: stock_items[index], quantity: 1, expires_at: expires_at)
  end

  it 'transitions reserved-past-TTL rows to EXPIRED (keeps history)' do
    due = make_reservation(0, expires_at: 1.minute.ago)
    described_class.perform_now

    expect(due.reload.state).to eq('expired')
    expect(due.reload.expired_at).to be_present
    expect(PallasTrade::StockReservation.where(order: order).count).to eq(1)
  end

  it 'is idempotent across repeated runs' do
    due = make_reservation(0, expires_at: 1.minute.ago)
    2.times { described_class.perform_now }

    expect(due.reload.state).to eq('expired')
    expect(PallasTrade::StockReservation.expired_state.where(order: order).count).to eq(1)
  end

  it 'leaves not-yet-expired RESERVED and terminal rows untouched' do
    active = make_reservation(0)
    committed = make_reservation(1)
    committed.update_column(:expires_at, 1.minute.ago)
    committed.commit!

    described_class.perform_now

    expect(active.reload.state).to eq('reserved')
    expect(committed.reload.state).to eq('committed')
  end
end
