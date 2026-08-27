# frozen_string_literal: true

require 'rails_helper'

# PRD-20260827-payments-实施-p4 合并支付载体
# AC-006：CombinationSettleJob 补偿队列——重试失败成员订单完成（幂等）
RSpec.describe PallasTrade::Payments::CombinationSettleJob, type: :job do
  let!(:store) { create(:store, code: 'pcom_settle_store') }
  let(:user) { create(:user) }

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
  let!(:combination) { create(:payment_combination, store: store, customer: user, amount: combined_amount, status: 'succeeded') }
  let!(:split1) { create(:payment_split, payment_combination: combination, order: order1, payment: nil, captured_amount: share) }
  let!(:split2) { create(:payment_split, payment_combination: combination, order: order2, payment: nil, captured_amount: share) }

  describe '#perform' do
    it 'AC-006 completes a pending member order on retry' do
      described_class.perform_now(combination.id, order2.id)
      expect(order2.reload).to be_completed
      expect(order2.payment_state).to eq('paid')
    end

    it 'is idempotent for an already-completed order' do
      order1.update_column(:state, 'complete')
      order1.update_column(:completed_at, Time.current)
      order1.update_column(:payment_state, 'paid')

      expect do
        described_class.perform_now(combination.id, order1.id)
      end.not_to change { order1.reload.updated_at }
    end

    it 'skips when the combination is not succeeded' do
      combination.update_column(:status, 'failed')
      expect do
        described_class.perform_now(combination.id, order2.id)
      end.not_to change { order2.reload.state }
    end
  end
end
