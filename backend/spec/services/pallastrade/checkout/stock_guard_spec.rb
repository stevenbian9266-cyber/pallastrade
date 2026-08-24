require 'rails_helper'

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化
# AC-015/016/017 — 下单库存校验 + 锁库存双模式
RSpec.describe PallasTrade::Checkout::StockGuard, type: :service do
  let(:store) { PallasTrade::Store.default }
  let(:user) { create(:user) }
  let(:variant) { create(:variant) }
  let(:stock_location) { create(:stock_location) }
  let!(:stock_item) do
    # backorderable: false 关键——backorderable 的 stock_item 会被 Reserve 跳过校验；
    # adjust_count_on_hand: false 防止 factory 把 count_on_hand 覆盖为 10
    create(:stock_item, variant: variant, stock_location: stock_location,
                        count_on_hand: 5, backorderable: false, adjust_count_on_hand: false)
  end
  let(:order) { create(:order, store: store, user: user) }

  before do
    # variant 可能带多个 stock_item（factory 副作用）；只保留唯一可校验的（backorderable=false）
    variant.stock_items.reload.where.not(id: stock_item.id).delete_all
  end

  def order_with_quantity(qty)
    create(:line_item, order: order, variant: variant, quantity: qty)
    order
  end

  after do
    PallasTrade::Config[:stock_reservation_strategy] = nil
  end

  it 'AC-015: 库存充足时通过校验' do
    order_with_quantity(3)
    result = described_class.call(order: order)
    expect(result).to be_success
  end

  it 'AC-015: 库存不足时拦截并返回 insufficient_stock' do
    order_with_quantity(6)
    result = described_class.call(order: order)
    expect(result).to be_failure
    expect(result.error.value[:code]).to eq(:insufficient_stock)
    expect(result.error.value[:message]).to be_present
  end

  it 'AC-016: 下单锁库存模式（默认）→ 校验并创建预留' do
    PallasTrade::Config[:stock_reservation_strategy] = 'order'
    order_with_quantity(3)
    expect { described_class.call(order: order) }
      .to change(PallasTrade::StockReservation, :count).by(1)
  end

  it 'AC-016: 支付锁库存模式 → 仅校验，不创建预留' do
    store.preferred_stock_reservation_strategy = 'payment'
    store.save!
    order_with_quantity(3)
    expect { described_class.call(order: order) }
      .not_to change(PallasTrade::StockReservation, :count)
    expect(PallasTrade::StockReservation.for_order(order)).to be_empty
  end

  it 'AC-017: 锁库存模式下库存不足同样拦截（支付锁仅校验）' do
    store.preferred_stock_reservation_strategy = 'payment'
    store.save!
    order_with_quantity(6)
    result = described_class.call(order: order)
    expect(result).to be_failure
    expect(result.error.value[:code]).to eq(:insufficient_stock)
  end
end
