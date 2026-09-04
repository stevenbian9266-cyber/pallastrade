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
      end.not_to(change { order1.reload.updated_at })
    end

    it 'skips when the combination is not succeeded' do
      combination.update_column(:status, 'failed')
      expect do
        described_class.perform_now(combination.id, order2.id)
      end.not_to(change { order2.reload.state })
    end
  end

  # RISK-01（2026-09-04，TXN-P2-0 §10）：standard 成员重试走 Carts::Complete
  describe 'with standard-flow member order (RISK-01)' do
    def pending_standard_member(total: 50.0)
      order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0,
                                             line_items_price: total)
      order.update_columns(
        state: 'pending', status: 'placed', submitted_at: Time.current,
        completed_at: nil, payment_state: nil, payment_total: 0
      )
      PallasTrade::OrderUpdater.new(order).update
      order.reload
    end

    let(:order_std) { pending_standard_member }
    let!(:combination) do
      create(:payment_combination, store: store, customer: user,
                                   amount: order_std.amount_due.to_f, status: 'succeeded')
    end
    let!(:split) do
      s = create(:payment_split, payment_combination: combination, order: order_std, payment: nil,
                                 captured_amount: order_std.amount_due.to_f)
      # 模拟 PaymentCombinations::Complete 阶段 1 已记账：member 订单 payment_total/payment_state
      # 已由组合入账写列（Carts::Complete 的 process_payments! 守卫依赖 payment_total）
      order_std.update_columns(payment_total: order_std.amount_due, payment_state: 'paid')
      s
    end

    it 'completes a standard pending member via Carts::Complete on retry' do
      described_class.perform_now(combination.id, order_std.id)
      expect(order_std.reload).to be_completed
      expect(order_std.state).to eq('paid')
      expect(order_std.payment_state).to eq('paid')
    end
  end
end
