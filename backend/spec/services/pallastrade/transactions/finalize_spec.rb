# frozen_string_literal: true

# PRD-20260904-payments-txn-p2-5 AC-501..505
require 'rails_helper'

RSpec.describe PallasTrade::Transactions::Finalize, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:user) { create(:user) }

  def pending_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         payment_state: nil, completed_at: nil)
    order.reload
  end

  def legacy_cart_order
    create(:order, store: store, user: user, state: 'cart', item_total: 50, total: 50)
  end

  def attach_transaction(order, amount: order.total)
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: order.currency.to_s, amount: amount
    )
    PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order,
                                          role: 'primary', amount_snapshot: amount)
    tx
  end

  def settle!(order, transaction, amount: order.total)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             status: 'completed', amount: amount,
                                             currency: order.currency.to_s, commerce_transaction: transaction)
    create(:payment, order: order, payment_method: payment_method, amount: amount,
                     state: 'completed', payment_session: session)
    session
  end

  def payment_confirmed(order)
    tx = attach_transaction(order)
    settle!(order, tx)
    tx.start_payment!
    tx.confirm_payment!
    tx
  end

  def call_finalize(transaction)
    described_class.call(transaction: transaction)
  end

  describe '#call' do
    it 'AC-501 payment_confirmed → finalizes participants → completed' do
      order = pending_order
      tx = payment_confirmed(order)

      result = call_finalize(tx)

      expect(result).to be_success
      expect(result.value[:action]).to eq(:finalized)
      expect(order.reload).to be_completed
      expect(tx.reload).to be_completed
      expect(tx.transaction_orders.reload.first.completion_status).to eq('completed')
    end

    it 'AC-502 repeated call on completed transaction is idempotent' do
      order = pending_order
      tx = payment_confirmed(order)

      expect(call_finalize(tx)).to be_success
      expect(call_finalize(tx)).to be_success

      expect(tx.reload).to be_completed
      expect(order.reload).to be_completed
      expect(order.payments.count).to eq(1)
    end

    it 'AC-503 created / payment_pending are rejected without state change' do
      order = pending_order
      tx = attach_transaction(order)

      result = call_finalize(tx)
      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('commerce_transaction_not_finalizable')
      expect(tx.reload).to be_created

      tx.start_payment!
      rejected = call_finalize(tx)
      expect(rejected).to be_failure
      expect(rejected.error.value[:code]).to eq('commerce_transaction_not_finalizable')
      expect(tx.reload).to be_payment_pending
    end

    it 'AC-504 participant failure → recovery_required + last_error finalize_failed' do
      order = legacy_cart_order
      tx = payment_confirmed(order)

      result = call_finalize(tx)

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('finalize_failed')
      expect(tx.reload).to be_recovery_required
      expect(tx.last_error_code).to eq('finalize_failed')
      expect(order.reload).not_to be_completed
    end

    it 'AC-505 recovery_required (already paid) → retry_finalizing → completed' do
      order = pending_order
      tx = payment_confirmed(order)
      tx.mark_recovery_required!
      expect(tx.reload).to be_recovery_required

      result = call_finalize(tx)

      expect(result).to be_success
      expect(result.value[:action]).to eq(:finalized)
      expect(order.reload).to be_completed
      expect(tx.reload).to be_completed
    end

    it 'returns failure for a nil transaction' do
      result = described_class.call(transaction: nil)
      expect(result).to be_failure
    end
  end
end
