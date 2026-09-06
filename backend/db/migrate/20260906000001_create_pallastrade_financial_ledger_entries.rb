# frozen_string_literal: true

# FIN-P4-2 (PRD-20260905-payments-fin-p4-2): CommerceTransaction 级不可变资金账本
# (Immutable Financial Journal)。posting 输入 = FIN-P4-1 FinancialFact（FR-4P1-40/FIN-INV-02）。
# - financial_ledger_entries: append-only 账本（entry_type/带符号 amount/currency/幂等 key/
#   reversal 自引用/state posted|reversed/effective_at vs recorded_at）
# - 不可变：amount/currency/source/entry_type/ownership 创建后禁原地改（模型层 ImmutableError +
#   before_update/update_columns 双层拦截）；仅 reversal 流转（state/reversed_at）由 Reverse 原语执行。
# - 并发收敛：idempotency_key UNIQUE + (reversal_of_id) WHERE state='posted' partial UNIQUE + 业务层 with_lock。
class CreatePallasTradeFinancialLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_financial_ledger_entries do |t|
      # 归属（P4 §12 命名纪律：commerce_transaction_id，非含糊 transaction_id）
      t.references :commerce_transaction, null: false, foreign_key: { to_table: :pallastrade_commerce_transactions }
      # 显式可空 source FK（与 FIN-P4-1 fact contract 对齐；去掉 polymorphic 冗余保引用完整性）
      t.references :order, foreign_key: { to_table: :pallastrade_orders }
      t.references :payment, foreign_key: { to_table: :pallastrade_payments }
      t.references :refund, foreign_key: { to_table: :pallastrade_refunds }
      t.references :payment_combination, foreign_key: { to_table: :pallastrade_payment_combinations }
      t.references :payment_split, foreign_key: { to_table: :pallastrade_payment_splits }

      t.string :entry_type, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false
      t.string :idempotency_key, null: false

      # reversal/状态
      t.references :reversal_of, foreign_key: { to_table: :pallastrade_financial_ledger_entries }
      t.string :state, null: false, default: 'posted'
      t.datetime :reversed_at

      # 时间语义：effective_at = 资金事实发生时间（fact）；recorded_at = 本地入账时间
      t.datetime :effective_at, null: false
      t.datetime :recorded_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      # provider 溯源（FIN-P4-5 填；本包不写业务语义，仅结构预留）
      t.string :provider
      t.string :provider_reference

      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :pallastrade_financial_ledger_entries, :idempotency_key, unique: true
    add_index :pallastrade_financial_ledger_entries, [:commerce_transaction_id, :entry_type]
    add_index :pallastrade_financial_ledger_entries, :state
    # 同一原 entry 至多一条有效(posted) reversal（FIN-INV-09）
    add_index :pallastrade_financial_ledger_entries, :reversal_of_id,
              unique: true, where: "state = 'posted'", name: 'idx_pallastrade_fin_ledger_active_reversal'
  end
end
