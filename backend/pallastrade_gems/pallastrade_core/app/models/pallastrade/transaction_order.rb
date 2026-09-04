# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-1 (PRD-20260904-checkout-txn-p2-1)
#
# TransactionOrder —— CommerceTransaction 与 Order 的参与者关联（1 Transaction : N Order）。
# role: primary | participant（首版最小集；fulfillment_child/balance_target 延后，
# 见 TXN-P2-0 §6.3）。amount_snapshot 为启动时该单 amount_due（证据，非计算源）。
# completion_status: pending | completed | failed（TXN-P2-5 Finalize 使用）。
module PallasTrade
  class TransactionOrder < PallasTrade.base_class
    ROLES = %w[primary participant].freeze
    COMPLETION_STATUSES = %w[pending completed failed].freeze

    belongs_to :commerce_transaction, class_name: 'PallasTrade::CommerceTransaction',
                                      foreign_key: :transaction_id,
                                      inverse_of: :transaction_orders
    belongs_to :order, class_name: 'PallasTrade::Order'

    validates :role, :completion_status, presence: true
    validates :role, inclusion: { in: ROLES }
    validates :completion_status, inclusion: { in: COMPLETION_STATUSES }
    validates :order_id, uniqueness: { scope: :transaction_id }
  end
end
