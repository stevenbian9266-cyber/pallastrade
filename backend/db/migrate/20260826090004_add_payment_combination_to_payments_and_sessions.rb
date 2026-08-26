# frozen_string_literal: true

# Order lifecycle P1 (2026-08-26): combined-payment carrier on payments and
# payment_sessions. Nullable — single-order payments are untouched. Keeps the
# existing PaymentSession <-> Payment 1:1 contract (one session, one payment,
# both optionally bound to a combination).
class AddPaymentCombinationToPaymentsAndSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :pallastrade_payments, :payment_combination, null: true,
                 foreign_key: { to_table: :pallastrade_payment_combinations }
    add_reference :pallastrade_payment_sessions, :payment_combination, null: true,
                 foreign_key: { to_table: :pallastrade_payment_combinations }
  end
end
