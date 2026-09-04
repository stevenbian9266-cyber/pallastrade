# frozen_string_literal: true

# PRD-20260904-payments-txn-p2-4 AC-411..417
require 'rails_helper'

RSpec.describe PallasTrade::Transactions::Recover, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:user) { create(:user) }

  def pending_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         payment_state: nil, completed_at: nil)
    order.reload
  end

  def completed_order
    order = pending_order
    order.update_columns(state: 'complete', completed_at: Time.current)
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

  def put_recovery_required(transaction)
    transaction.start_payment!
    transaction.confirm_payment!
    transaction.mark_recovery_required!
    transaction
  end

  def settle!(order, transaction, amount: order.total)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             status: 'completed', amount: amount,
                                             currency: order.currency.to_s, commerce_transaction: transaction)
    create(:payment, order: order, payment_method: payment_method, amount: amount,
                     state: 'completed', payment_session: session)
    session
  end

  def recover(transaction)
    described_class.call(transaction: transaction)
  end

  describe '#call' do
    it 'AC-411 UNPAID (no sessions) → retry_payment to payment_pending' do
      order = pending_order
      tx = put_recovery_required(attach_transaction(order))

      result = recover(tx)

      expect(result).to be_success
      expect(result.value[:action]).to eq(:retry_payment)
      expect(tx.reload).to be_payment_pending
      expect(tx.recovery_attempts).to eq(1)
    end

    it 'AC-412 PAID + order incomplete → finalize participants → completed' do
      order = pending_order
      tx = attach_transaction(order)
      settle!(order, tx)
      put_recovery_required(tx)

      result = recover(tx)

      expect(result).to be_success
      expect(result.value[:action]).to eq(:finalized)
      expect(order.reload).to be_completed
      expect(tx.reload).to be_completed
      expect(tx.transaction_orders.reload.first.completion_status).to eq('completed')
    end

    it 'AC-413 PAID + all participants already completed → repair_completed' do
      order = completed_order
      tx = attach_transaction(order)
      settle!(order, tx) # 提供本地已收证据
      put_recovery_required(tx)

      result = recover(tx)
      expect(result).to be_success
      expect(result.value[:action]).to eq(:repair_completed)
      expect(tx.reload).to be_completed
    end

    it 'AC-414 AMBIGUOUS (provider pending) → manual_review' do
      order = pending_order
      tx = attach_transaction(order)
      create(:bogus_payment_session, order: order, payment_method: payment_method,
                                     status: 'pending', amount: order.total,
                                     currency: order.currency.to_s, commerce_transaction: tx)
      put_recovery_required(tx)

      result = recover(tx)

      expect(result).to be_success
      expect(result.value[:action]).to eq(:manual_review)
      expect(tx.reload).to be_manual_review
    end

    it 'AC-415 repeated recover is idempotent (no second finalize / no new payment)' do
      order = pending_order
      tx = attach_transaction(order)
      settle!(order, tx)
      put_recovery_required(tx)

      first = recover(tx)
      expect(first).to be_success
      expect(tx.reload).to be_completed

      second = recover(tx)
      expect(second).to be_failure
      expect(second.error.value[:code]).to eq('commerce_transaction_not_recoverable')

      expect(order.reload).to be_completed
      expect(order.payments.count).to eq(1)
      expect(order.payment_sessions.count).to eq(1)
    end

    it 'AC-416 non-recoverable state → failure, state unchanged' do
      order = pending_order
      tx = attach_transaction(order)
      tx.start_payment! # payment_pending

      result = recover(tx)

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('commerce_transaction_not_recoverable')
      expect(tx.reload).to be_payment_pending
    end

    it 'AC-417 finalize failure → stays recovery_required + last_error recorded' do
      order = legacy_cart_order
      tx = attach_transaction(order, amount: order.total)
      settle!(order, tx)
      put_recovery_required(tx)

      result = recover(tx)

      expect(result).to be_failure
      expect(result.error.value[:code]).to eq('finalize_failed')
      expect(tx.reload).to be_recovery_required
      expect(tx.last_error_code).to eq('finalize_failed')
      expect(tx.recovery_attempts).to eq(1)
    end

    it 'returns failure for a nil transaction' do
      result = described_class.call(transaction: nil)
      expect(result).to be_failure
    end
  end
end
