# frozen_string_literal: true

# TXN-P2-1 (PRD-20260904-checkout-txn-p2-1): durable commerce transaction
# orchestration context + participant join.
# - commerce_transactions: 一次商业交易的持久化生命周期（state/purpose/quote
#   绑定/immutable snapshot 证据/审计时间戳/recovery 元数据）
# - transaction_orders: 交易 ↔ 订单参与者（role/amount_snapshot/completion_status）
# 注意：不引入 lock_version 列（AR locking_column 与 state_machines 冲突，CHK-P1-2
# 教训）；并发收敛由业务层 with_lock/唯一约束承担（TXN-P2-2）。
class CreatePallasTradeCommerceTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_commerce_transactions do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      # customer 可空：guest 交易（与 PaymentSession 一致）
      t.references :customer, foreign_key: { to_table: :pallastrade_users }
      # 组合支付时 1:1 绑定（TXN-P2-2/5 起接；此处仅结构预留）
      t.references :payment_combination, foreign_key: { to_table: :pallastrade_payment_combinations }

      t.string :state, null: false, default: 'created'
      t.string :purpose, null: false
      t.string :currency, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false, default: 0

      # quote 绑定（TXN-P2-0 §5.3 snapshot 冻结列）
      t.integer :checkout_version
      t.string :price_version
      t.string :snapshot_fingerprint
      t.jsonb :snapshot_data, default: {}

      # 生命周期时间戳
      t.datetime :started_at
      t.datetime :payment_confirmed_at
      t.datetime :finalizing_at
      t.datetime :completed_at
      t.datetime :recovery_required_at
      t.datetime :canceled_at
      t.datetime :manual_review_at

      # recovery 元数据
      t.integer :recovery_attempts, null: false, default: 0
      t.string :last_error_code
      t.string :last_error_class
      t.string :last_error_message

      t.timestamps
    end
    add_index :pallastrade_commerce_transactions, :state
    add_index :pallastrade_commerce_transactions, [:store_id, :state]

    create_table :pallastrade_transaction_orders do |t|
      t.references :transaction, null: false, foreign_key: { to_table: :pallastrade_commerce_transactions }
      t.references :order, null: false, foreign_key: { to_table: :pallastrade_orders }
      t.string :role, null: false, default: 'participant'
      t.decimal :amount_snapshot, precision: 10, scale: 2
      t.string :completion_status, null: false, default: 'pending'
      t.timestamps
    end
    add_index :pallastrade_transaction_orders, [:transaction_id, :order_id], unique: true
  end
end
