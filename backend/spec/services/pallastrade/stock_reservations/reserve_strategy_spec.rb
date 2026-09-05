# frozen_string_literal: true

require 'rails_helper'

# PRD-20260828-checkout-p8 AC-005：锁库存双模式（:order 默认 / :payment 支付后锁）
RSpec.describe PallasTrade::StockReservations::Reserve, type: :service do
  let!(:store) { create(:store, code: 'reserve_strategy_store') }
  let!(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variant) { create(:product, store: store).master }
  let(:stock_item) { variant.stock_items.where(stock_location: stock_location).first }
  let!(:order) { create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 10, variants: [variant]) }

  before do
    # product factory 已 propagate stock_item 到 WH-R；调整可用库存
    stock_item.update_column(:count_on_hand, 5)
    stock_item.update_column(:backorderable, false)
  end

  describe '#call' do
    it 'AC-005 :order (default) creates reservations' do
      result = described_class.call(order: order)

      expect(result.success?).to be true
      expect(PallasTrade::StockReservation.where(order: order).count).to eq(1)
    end

    it 'AC-005 :payment (validate_only) checks stock without creating reservations' do
      result = described_class.call(order: order, validate_only: true)

      expect(result.success?).to be true
      expect(PallasTrade::StockReservation.where(order: order).count).to eq(0)
    end

    it 'AC-005 :payment (validate_only) still fails on insufficient stock' do
      # 可用 1 < 数量 2 → failure（Reserve 将 InsufficientStockError 转 failure 返回）
      order.line_items.first.update!(quantity: 2)
      order.line_items.reload
      stock_item.update_column(:count_on_hand, 1)

      result = described_class.call(order: order, validate_only: true)

      expect(result.failure?).to be true
      expect(result.error.to_s).to include('has only 1 available')
    end
  end

  describe 'Carts::Complete with :payment strategy' do
    let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }
    let(:cart) do
      cart = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 10, variants: [variant], shipment_cost: 0)
      cart.shipments.each do |s|
        s.shipping_rates.destroy_all
        s.add_shipping_method(create(:free_shipping_method), true)
      end
      # 推进到 payment 状态固化金额，再重置回 cart 供 Complete 完成
      cart.next until cart.payment? || cart.complete? || cart.errors.any?
      cart.update_columns(state: 'cart', completed_at: nil)
      cart.line_items.reload
      PallasTrade::OrderUpdater.new(cart).update
      cart.reload
      cart
    end
    let!(:payment) do
      create(:payment, order: cart, amount: cart.total, state: 'completed', payment_method: payment_method)
    end

    before do
      allow(PallasTrade::Config).to receive(:[]).and_call_original
      allow(PallasTrade::Config).to receive(:[]).with(:stock_reservation_strategy).and_return('payment')
      allow(PallasTrade::Config).to receive(:[]).with(:auto_split_orders).and_return([])
      allow(PallasTrade::Config).to receive(:[]).with(:checkout_preflight_enabled).and_return(false)
      stock_item.update_column(:count_on_hand, 5)
      stock_item.update_column(:backorderable, false)
    end

    it 'AC-005 completes checkout under :payment strategy (payment-triggered reservation does not break completion)' do
      # :payment 模式 cart 操作只校验（不建 reservation），Carts::Complete 支付确认后
      # Reserve → finalize（物理扣减）→ INV-P3-1/3 Commit（COMMITTED，不再硬删除）
      result = PallasTrade::Carts::Complete.call(cart: cart)

      expect(result.success?).to be true
      expect(cart.reload).to be_completed
      rows = PallasTrade::StockReservation.where(order: cart)
      expect(rows.count).to eq(1)
      expect(rows.first.state).to eq('committed')
      expect(rows.first.committed_at).to be_present
    end
  end
end
