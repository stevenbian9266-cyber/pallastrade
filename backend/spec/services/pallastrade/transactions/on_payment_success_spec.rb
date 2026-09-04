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
