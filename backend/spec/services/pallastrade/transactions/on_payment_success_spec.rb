# frozen_string_literal: true

# PRD-20260904-payments-txn-p2-5 AC-511..513
require 'rails_helper'

RSpec.describe PallasTrade::Transactions::OnPaymentSuccess, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:user) { create(:user) }

  def pending_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         payment_state: nil, completed_at: nil)
    order.reload
  end

  def settle!(order, transaction = nil, status: 'completed')
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             status: status, amount: order.total,
                                             currency: order.currency.to_s,
                                             commerce_transaction: transaction)
    create(:payment, order: order, payment_method: payment_method, amount: order.total,
                     state: 'completed', payment_session: session)
    session
  end

  def call_handler(payment_session)
    described_class.call(payment_session: payment_session)
  end

  describe '#call' do
    it 'AC-511 session with transaction (payment_pending) → confirm + Finalize → completed' do
      order = pending_order
      tx = PallasTrade::CommerceTransaction.create!(
        store: store, purpose: 'purchase', currency: order.currency.to_s, amount: order.total
      )
      PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order,
                                            role: 'primary', amount_snapshot: order.total)
      session = settle!(order, tx)
      tx.start_payment! # payment_pending（资金刚在本地验证成功）

      result = call_handler(session)

      expect(result).to be_success
      expect(result.value[:mode]).to eq(:finalized)
      expect(tx.reload).to be_completed
      expect(order.reload).to be_completed
    end

    it 'AC-512 session without transaction → legacy Carts::Complete behavior' do
      order = pending_order
      session = settle!(order) # 无 commerce_transaction（legacy/存量）

      result = call_handler(session)

      expect(result).to be_success
      expect(result.value[:mode]).to eq(:legacy_completed)
      expect(order.reload).to be_completed
    end

    # TXN-P2 组合 txn 化（PRD-20260905-checkout-paymentcombination-txn-化）AC-3：
    # 组合 txn PSP 成功 → confirm_payment! → Finalize（组合分支：入账 Settlement + 成员完成）
    it 'AC-3 combination transaction on payment success settles and completes all members' do
      o1 = pending_order
      o2 = pending_order
      combo_amount = (o1.total + o2.total).to_f
      currency = o1.currency.to_s
      combination = PallasTrade::PaymentCombination.create!(store: store, customer: user,
                                                            currency: currency, amount: combo_amount)
      combination.process!
      [o1, o2].each do |o|
        PallasTrade::PaymentSplit.create!(payment_combination: combination, order: o,
                                          currency: o.currency.to_s, authorized_amount: 0,
                                          captured_amount: 0, refunded_amount: 0)
      end

      tx = PallasTrade::CommerceTransaction.create!(store: store, customer: user,
                                                    payment_combination: combination,
                                                    purpose: 'combined_payment',
                                                    currency: currency, amount: combo_amount)
      PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: o1, role: 'primary', amount_snapshot: o1.total)
      PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: o2, role: 'participant', amount_snapshot: o2.total)

      session = settle!(o1, tx)
      session.update!(payment_combination: combination)
      tx.start_payment! # created → payment_pending

      result = call_handler(session)

      expect(result).to be_success
      expect(result.value[:mode]).to eq(:finalized)
      expect(tx.reload).to be_completed
      expect(combination.reload).to be_succeeded
      expect(o1.reload).to be_completed
      expect(o2.reload).to be_completed
      expect(combination.payments.count).to eq(1)          # 一个 Payment 挂组合
      expect(o1.reload.payments.count).to eq(0)            # 成员无独立 payment（转移至组合）
      expect(o1.reload.payment_state).to eq('paid')
    end

    it 'AC-513 repeated call is idempotent (no duplicate finalize / payment)' do
      order = pending_order
      tx = PallasTrade::CommerceTransaction.create!(
        store: store, purpose: 'purchase', currency: order.currency.to_s, amount: order.total
      )
      PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order,
                                            role: 'primary', amount_snapshot: order.total)
      session = settle!(order, tx)
      tx.start_payment!

      expect(call_handler(session)).to be_success
      expect(call_handler(session)).to be_success

      expect(tx.reload).to be_completed
      expect(order.reload).to be_completed
      expect(order.payments.count).to eq(1)
    end

    it 'returns failure for a nil payment session' do
      result = described_class.call(payment_session: nil)
      expect(result).to be_failure
    end
  end
end
