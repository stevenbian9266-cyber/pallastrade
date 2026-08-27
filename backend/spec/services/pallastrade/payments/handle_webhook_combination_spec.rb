# frozen_string_literal: true

require 'rails_helper'

# PRD-20260827-payments-实施-p4 合并支付载体
# AC-007：HandleWebhook 对挂组合的 session 走 PaymentCombinations::Complete
RSpec.describe PallasTrade::Payments::HandleWebhook, type: :service do
  let!(:store) { create(:store, code: 'pcom_webhook_store') }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }

  # order_with_line_items：含地址/shipment；固定运费 0 并移除 selected_shipping_rate
  def unpaid_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0)
    order.shipments.each do |s|
      s.shipping_rates.destroy_all
      s.add_shipping_method(create(:free_shipping_method), true)
    end
    # 推进到 payment 状态固化含税金额，再重置回 cart
    order.next until order.payment? || order.complete? || order.errors.any?
    order.update_columns(state: 'cart', completed_at: nil)
    order.line_items.reload
    PallasTrade::OrderUpdater.new(order).update
    order.reload
    order
  end

  let(:order1) { unpaid_order }
  let(:order2) { unpaid_order }
  let!(:combined_amount) { (order1.amount_due + order2.amount_due).to_f }
  let!(:share) { order1.amount_due.to_f }
  let!(:combination) { create(:payment_combination, store: store, customer: user, amount: combined_amount) }
  let!(:split1) { create(:payment_split, payment_combination: combination, order: order1, payment: nil) }
  let!(:split2) { create(:payment_split, payment_combination: combination, order: order2, payment: nil) }
  let!(:session) do
    create(:bogus_payment_session, order: order1, payment_method: payment_method,
                                   amount: combined_amount, payment_combination: combination)
  end

  it 'AC-007 routes combined-payment success through PaymentCombinations::Complete' do
    result = described_class.call(
      payment_method: payment_method,
      action: :captured,
      payment_session: session,
      metadata: {}
    )

    expect(result.success?).to be true
    expect(combination.reload.status).to eq('succeeded')
    expect(combination.payments.count).to eq(1)
    expect(combination.payments.first).to be_completed
    expect(split1.reload.captured_amount).to eq(share)
    expect(split2.reload.captured_amount).to eq(share)
    expect(order1.reload).to be_completed
    expect(order2.reload).to be_completed
  end

  it 'AC-007 leaves single-order webhook flow untouched (no combination)' do
    plain = unpaid_order
    plain_session = create(:bogus_payment_session, order: plain, payment_method: payment_method)

    result = described_class.call(
      payment_method: payment_method,
      action: :captured,
      payment_session: plain_session,
      metadata: {}
    )
    puts "DEBUG single error=#{result.error}" unless result.success?

    expect(result.success?).to be true
    expect(plain.reload).to be_completed
  end
end
