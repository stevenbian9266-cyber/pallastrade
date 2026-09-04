# frozen_string_literal: true

# TXN-P2-2 (PRD-20260904-api-txn-p2-2): PaymentSession 归属 CommerceTransaction
# （可空；存量/legacy session 为 NULL，不回溯）。
class AddTransactionToPallasTradePaymentSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :pallastrade_payment_sessions, :transaction,
                  foreign_key: { to_table: :pallastrade_commerce_transactions },
                  index: true
  end
end
