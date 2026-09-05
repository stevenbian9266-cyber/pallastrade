# frozen_string_literal: true

# PALLAS-CUSTOM: bugfix (2026-09-05, dev 冒烟发现) —— Bogus gateway 的
# complete_payment_session 原先只 complete 会话、不落账本地 Payment。
# 单订单 txn 直接 complete（orders payment_sessions complete，无 webhook）时：
#   session completed → Transactions::OnPaymentSuccess → Finalize →
#   Carts::Complete 标准分支要求已存在 completed Payment（否则 no_payment_found
#   → recovery_required）；且 Bogus 无 webhook，Payment 永远不会被创建 →
#   Recover/Sweeper 也无法收尾（死循环）。Stripe/PayPal 均已在 complete 内建
#   Payment，Bogus 缺 parity。修复后 complete_payment_session 对齐 Settlement
#   配方：find_or_create_payment! + skip_source_requirement + complete!。
# 本 spec 复刻运行时链路（controller complete 顺序）：
#   gateway.complete_payment_session → Transactions::OnPaymentSuccess → Finalize。
require 'rails_helper'

RSpec.describe PallasTrade::Gateway::Bogus, type: :model do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:user) { create(:user) }

  def pending_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         payment_state: nil, completed_at: nil)
    order.reload
  end

  def attach_transaction(order, amount: order.total)
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: order.currency.to_s, amount: amount
    )
    PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order,
                                          role: 'primary', amount_snapshot: amount)
    tx.start_payment!
    tx
  end

  describe '#complete_payment_session' do
    it '单订单 txn 直接 complete：落账 Payment → 会话 completed → 订单 paid、txn completed' do
      order = pending_order
      tx = attach_transaction(order)
      session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                               status: 'pending', amount: order.total,
                                               currency: order.currency.to_s,
                                               commerce_transaction: tx)

      # 1) 镜像 orders payment_sessions complete：gateway 完成会话（现应落账 Payment）
      payment_method.complete_payment_session(payment_session: session)

      expect(session.reload.status).to eq('completed')
      payment = session.reload.payment
      expect(payment).to be_present
      expect(payment).to be_completed
      expect(payment.amount.to_f).to eq(order.total.to_f)
      expect(payment.payment_session_id).to eq(session.id)

      # 2) 镜像 controller 后续：OnPaymentSuccess → Finalize → 订单完成
      result = PallasTrade::Transactions::OnPaymentSuccess.call(payment_session: session.reload)
      expect(result).to be_success
      expect(result.value[:mode]).to eq(:finalized)

      expect(order.reload).to be_completed
      expect(tx.reload).to be_completed
      expect(order.payment_state).to eq('paid')
    end

    it '幂等：completed 会话再次 complete 不重复建 Payment' do
      order = pending_order
      tx = attach_transaction(order)
      session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                               status: 'pending', amount: order.total,
                                               currency: order.currency.to_s,
                                               commerce_transaction: tx)

      payment_method.complete_payment_session(payment_session: session)
      expect(session.reload.payment).to be_completed

      payment_method.complete_payment_session(payment_session: session.reload)
      expect(session.reload.status).to eq('completed')
      expect(order.payments.count).to eq(1)
    end
  end
end
