# frozen_string_literal: true

require 'rails_helper'

# INV-P3-5 (PRD-20260905-shipping-...) FR-043/044：
# Recovery 阶段化 —— PaymentFact 判定后再按 InventoryFact 决策：
# PAID + RELEASED（critical）→ manual_review；PAID + RESERVED → 继续 canonical finalize。
RSpec.describe PallasTrade::Transactions::Recover, type: :service do
  let(:store) { create(:store, code: 'rec_inv_store') }
  let(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variant) { create(:product, store: store).master }
  let(:stock_item) { create(:stock_item, variant: variant, stock_location: stock_location) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }

  def build_paid_transaction
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 10, total: 10, payment_state: 'balance_due',
                           currency: store.default_currency, email: 'buyer@example.com')
    create(:line_item, order: order, variant: variant, quantity: 1, price: 10)
    order.line_items.reload

    tx = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase',
                                                  currency: order.currency, amount: order.amount_due)
    PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order, role: 'primary',
                                          amount_snapshot: order.amount_due)

    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             amount: order.amount_due, status: 'completed')
    session.update_column(:transaction_id, tx.id)
    create(:payment, order: order, amount: order.amount_due, state: 'completed',
                     payment_session: session, payment_method: payment_method)

    # 构造 recovery_required（payment_confirmed → mark_recovery_required）
    tx.start_payment!
    tx.confirm_payment!
    tx.mark_recovery_required!
    [tx, order]
  end

  before do
    variant.update_column(:track_inventory, true)
    stock_item.update_columns(count_on_hand: 5, backorderable: false)
  end

  it 'PAID + RELEASED incomplete → manual_review (不猜、不重复 finalize)' do
    tx, order = build_paid_transaction
    row = create(:stock_reservation, order: order, line_item: order.line_items.first,
                                     stock_item: stock_item, quantity: 1)
    row.update!(release_reason: 'manual_test')
    row.release!

    result = described_class.call(transaction: tx)

    expect(result).to be_success
    expect(result.value[:action]).to eq(:manual_review)
    expect(result.value[:inventory_fact]).to eq(:released)
    expect(tx.reload.state).to eq('manual_review')
  end

  it 'PAID + RESERVED incomplete → not manual_review (proceeds to canonical finalize)' do
    tx, order = build_paid_transaction
    row = create(:stock_reservation, order: order, line_item: order.line_items.first,
                                     stock_item: stock_item, quantity: 1)
    expect(row.state).to eq('reserved')

    result = described_class.call(transaction: tx)

    # 关键契约：PAID+RESERVED 不得 manual_review，继续 finalize（可能成功 → commit，
    # 或失败 → recovery_required/failure，均由 Finalize 幂等收口）
    action = result.value.try(:[], :action)
    expect(action).not_to eq(:manual_review)
    expect(tx.reload.state).not_to eq('manual_review')
  end
end
