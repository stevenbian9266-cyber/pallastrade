# frozen_string_literal: true

require 'rails_helper'

# PRD-20260827-payments-实施-p4 合并支付载体
# AC-004/005/006/008：PaymentCombinations::Complete 幂等完成 / 先入账后完成 / 部分失败补偿 / 1:1
RSpec.describe PallasTrade::Payments::PaymentCombinations::Complete, type: :service do
  let!(:store) { create(:store, code: 'pcom_complete_store') }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }

  # order_with_line_items：含地址/shipment；固定运费 0 并移除 selected_shipping_rate，
  # 避免 complete 时 update_amounts 用默认运费重算漂移 total
  def unpaid_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0)
    order.shipments.each do |s|
      s.shipping_rates.destroy_all
      s.add_shipping_method(create(:free_shipping_method), true)
    end
    # 推进到 payment 状态触发 create_tax_charge! 固化含税金额，再重置回 cart 供 Complete 完成
    order.next until order.payment? || order.complete? || order.errors.any?
    order.update_columns(state: 'cart', completed_at: nil)
    order.line_items.reload
    PallasTrade::OrderUpdater.new(order).update
    order.reload
    order
  end

  let(:order1) { unpaid_order }
  let(:order2) { unpaid_order }
  # let! 在 example 前（订单未完成、未记账）捕获金额；惰性 let 在断言时才求值会拿到 0
  let!(:combined_amount) { (order1.amount_due + order2.amount_due).to_f }
  let!(:share) { order1.amount_due.to_f }
  let!(:combination) { create(:payment_combination, store: store, customer: user, amount: combined_amount) }
  let!(:split1) { create(:payment_split, payment_combination: combination, order: order1, payment: nil) }
  let!(:split2) { create(:payment_split, payment_combination: combination, order: order2, payment: nil) }
  let!(:session) do
    create(:bogus_payment_session, order: order1, payment_method: payment_method,
                                   amount: combined_amount, payment_combination: combination)
  end

  describe '#call' do
    it 'AC-005 completes combination + one payment + splits + member orders' do
      result = described_class.call(payment_session: session)
      expect(result.success?).to be true

      expect(combination.reload.status).to eq('succeeded')
      payment = combination.payments.first
      expect(payment).to be_present
      expect(payment).to be_completed
      expect(payment.order_id).to be_nil
      expect(payment.amount).to eq(combined_amount)

      expect(split1.reload.captured_amount).to eq(share)
      expect(split1.payment_id).to eq(payment.id)
      expect(split2.reload.captured_amount).to eq(share)

      expect(order1.reload).to be_completed
      expect(order1.payment_state).to eq('paid')
      expect(order2.reload).to be_completed
      expect(order2.payment_state).to eq('paid')
    end

    it 'AC-008 keeps session <-> payment 1:1 (exactly one payment on the combination)' do
      described_class.call(payment_session: session)
      expect(combination.reload.payments.count).to eq(1)
      expect(order1.reload.payment_sessions.count).to eq(1)
    end

    it 'AC-004 is idempotent across repeated calls (webhook + API double-path)' do
      described_class.call(payment_session: session)

      expect do
        described_class.call(payment_session: session)
      end.not_to change { combination.reload.payments.count }

      expect(combination.reload.payment_splits.count).to eq(2)
      expect(split1.reload.captured_amount).to eq(share)
      expect(order1.reload).to be_completed
      expect(order2.reload).to be_completed
    end

    it 'AC-004 short-circuits when the combination is already succeeded' do
      combination.succeed!
      result = described_class.call(combination: combination)
      expect(result.success?).to be true
      expect(combination.reload.payments.count).to eq(0)
    end

    it 'AC-006 keeps the captured payment when one member order fails to complete' do
      # order2 的商品已下架 → 无法推进到 complete（真实失败，不 stub）
      order2.line_items.each { |li| li.variant.update_column(:discontinue_on, Time.current) }

      result = described_class.call(payment_session: session)
      expect(result.success?).to be true

      # 已入账支付保留
      expect(combination.reload.status).to eq('succeeded')
      expect(combination.payments.count).to eq(1)
      expect(combination.payments.first).to be_completed

      # order1 完成，order2 失败标 balance_due（资金已入账，order2 未扣两次款）
      expect(order1.reload).to be_completed
      expect(order2.reload).not_to be_completed
      expect(order2.payment_state).to eq('balance_due')
      expect(order2.payment_total).to eq(share)
    end
  end
end
