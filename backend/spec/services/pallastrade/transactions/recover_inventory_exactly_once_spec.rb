# frozen_string_literal: true

require 'rails_helper'

# INV-P3 审计收口 D6 (2026-09-05): RV-I03 —— PAID + Finalize/Recover 消费成功后，
# 重复 Recover / Finalize 不产生第二条等价 StockMovement、不重复 Commit（exactly-once，
# 依赖既有 finalize/order.completed 幂等 + RESERVED→COMMITTED state guard）。
# 补齐 PRD §8 “关键集成测试规则：RV-I03 重复执行不增加第二条等价 StockMovement”。
# AC-3009/3010（canonical finalize 唯一物理扣减，无第二套）、AC-3011/3024（消费后 COMMITTED）、
# AC-3013（失败→recovery_required）、AC-3014（PAID+RESERVED→finalize→COMMITTED）、AC-3015（重复不重复扣）。
RSpec.describe PallasTrade::Transactions::Recover, type: :service do
  let!(:store) { create(:store, code: 'rv_i03_store') }
  let!(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variant) { create(:product, store: store).master }
  let!(:stock_item) { create(:stock_item, variant: variant, stock_location: stock_location) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  before do
    variant.update_column(:track_inventory, true)
    stock_item.update_columns(count_on_hand: 5, backorderable: false)
  end

  def pending_standard_order
    order = create(:order_with_line_items, store: store, line_items_count: 1,
                                           variants: [variant], line_items_price: 10, shipment_cost: 0)
    order.shipments.each do |shipment|
      shipment.shipping_rates.destroy_all
      shipment.add_shipping_method(create(:free_shipping_method), true)
    end
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         payment_state: nil, completed_at: nil)
    order.line_items.reload
    order
  end

  def attach_and_reserve(order)
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: order.currency.to_s, amount: order.amount_due
    )
    PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order,
                                          role: 'primary', amount_snapshot: order.amount_due)
    reserve = PallasTrade::Transactions::ReserveInventory.call(transaction: tx)
    expect(reserve).to be_success
    tx
  end

  # 资金已入账（本地 completed Payment）+ 交易推进到 recovery_required（模拟 Finalize 失败
  # 一次后由运维/Sweeper 触发恢复）。Reservation 保持 RESERVED 且绑定 txn。
  def settle_and_flag_recovery(order, transaction)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             status: 'completed', amount: order.total,
                                             currency: order.currency.to_s,
                                             commerce_transaction: transaction)
    create(:payment, order: order, payment_method: payment_method, amount: order.total,
                     state: 'completed', payment_session: session)
    transaction.start_payment!
    transaction.confirm_payment!
    transaction.mark_recovery_required!
    transaction
  end

  def movements
    PallasTrade::StockMovement.where(stock_item_id: stock_item.id).count
  end

  it 'RV-I03: recover finalizes once (StockMovement exactly once + COMMITTED); repeat recover/finalize adds nothing' do
    order = pending_standard_order
    tx = attach_and_reserve(order)
    reservation = PallasTrade::StockReservation.reserved.where(order: order).first
    expect(reservation).to be_present
    settle_and_flag_recovery(order, tx)

    # 第一次恢复：canonical finalize → 物理扣减 1 → Commit（RESERVED→COMMITTED）
    first = described_class.call(transaction: tx)
    expect(first).to be_success
    expect(first.value[:action]).to eq(:finalized)
    expect(order.reload).to be_completed
    expect(tx.reload).to be_completed
    expect(reservation.reload.state).to eq('committed')
    expect(reservation.reload.committed_at).to be_present
    expect(movements).to eq(1)
    expect(stock_item.reload.count_on_hand).to eq(4)

    # 重复 Recover → 交易已 completed → 不二次 finalize
    second = described_class.call(transaction: tx)
    expect(second).to be_failure
    expect(second.error.value[:code]).to eq('commerce_transaction_not_recoverable')

    # 重复 Finalize → completed 短路，仍无第二条 StockMovement / 无重复 Commit
    again = PallasTrade::Transactions::Finalize.call(transaction: tx)
    expect(again).to be_success

    expect(movements).to eq(1)
    expect(stock_item.reload.count_on_hand).to eq(4)
    expect(PallasTrade::StockReservation.committed.where(order: order).count).to eq(1)
    expect(PallasTrade::StockReservation.where(order: order).count).to eq(1)
  end
end
