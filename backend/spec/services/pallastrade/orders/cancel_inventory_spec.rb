# frozen_string_literal: true

require 'rails_helper'

# INV-P3-4 (PRD-20260905-shipping-...) FR-032/033/034：
# Orders::Cancel 后释放"未支付"的 RESERVED → RELEASED；PAID 不自动 Release。
RSpec.describe PallasTrade::Orders::Cancel, type: :service do
  let(:store) { create(:store, code: 'cancel_inv_store') }
  let(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variant) { create(:product, store: store).master }
  let(:stock_item) { create(:stock_item, variant: variant, stock_location: stock_location) }

  # 最简 pending 订单（无 shipments/payments → after_cancel 无副作用）
  def build_pending_order
    o = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                       item_total: 10, total: 10, payment_state: 'balance_due',
                       currency: store.default_currency, email: 'buyer@example.com')
    create(:line_item, order: o, variant: variant, quantity: 1, price: 10)
    o.line_items.reload
    o
  end

  before do
    variant.update_column(:track_inventory, true)
    stock_item.update_columns(count_on_hand: 5, backorderable: false)
  end

  it 'FR-033 releases still-RESERVED reservations when an unpaid order is canceled' do
    order = build_pending_order
    row = create(:stock_reservation, order: order, line_item: order.line_items.first,
                                     stock_item: stock_item, quantity: 1)

    result = described_class.call(order: order, reason: 'customer')

    expect(result).to be_success
    expect(order.reload.state).to eq('canceled')
    expect(row.reload.state).to eq('released')
    expect(row.reload.release_reason).to eq('order_canceled')
  end

  it 'FR-032/034 does NOT release reservations on a paid order (PAID 取消走售后/退款域)' do
    order = build_pending_order
    row = create(:stock_reservation, order: order, line_item: order.line_items.first,
                                     stock_item: stock_item, quantity: 1)
    create(:payment, order: order, amount: order.total, state: 'completed',
                     payment_method: create(:bogus_payment_method, store: store))

    # Orders::Cancel 对"已付订单"本身不可取消（after_cancel 无 payment cancel 转移 → failure），
    # 关键契约：任何取消尝试都不得把该 PAID 订单的 reservation Release（INV-I09）。
    result = described_class.call(order: order, reason: 'staff')

    expect(row.reload.state).to eq('reserved')
    # success（若可取消）或 failure（已付不可取消）均不允许 RELEASED
    expect(row.reload).not_to be_terminal if result.success?
  end
end
