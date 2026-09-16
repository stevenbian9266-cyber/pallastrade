# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片1（PRD-20260916-payments-d13-reconciliation-cases；业务方案 §70.1）——
# 对账差异队列的**持久化案例**（P4-7/P4-8 明确「reconciliation 结果不落表，由持久化形态决定」，
# 本迁移即该决策落地）：
#   * pallastrade_reconciliation_cases —— 差异案例（交易级/源级），唯一键 = dedupe_key
#     （`txn:<transaction_id>:<signature>`；signature = 排序去重后的原因码）。
#   * pallastrade_reconciliation_case_notes —— 案例备注（留痕，不覆盖历史）。
# additive：仅新增两张表 + 索引；不改任何既有表/语义（零回填）。
class CreatePallasTradeReconciliationCases < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_reconciliation_cases do |t|
      t.references :store, null: false, index: true, foreign_key: { to_table: :pallastrade_stores }
      t.references :transaction, index: true, foreign_key: { to_table: :pallastrade_commerce_transactions }
      t.references :payment, index: true, foreign_key: { to_table: :pallastrade_payments }
      t.references :refund, index: true, foreign_key: { to_table: :pallastrade_refunds }
      t.references :assignee, index: true, foreign_key: { to_table: :pallastrade_admin_users }

      t.string :kind, null: false
      t.string :status, null: false, default: 'open'
      t.string :difference_type, null: false
      t.string :severity, null: false
      t.string :provider
      t.string :currency, limit: 10
      t.decimal :expected_amount, precision: 12, scale: 2
      t.decimal :observed_amount, precision: 12, scale: 2
      t.jsonb :reason_codes, null: false, default: []
      t.jsonb :summary, null: false, default: {}

      t.string :dedupe_key, null: false
      t.integer :occurrences, null: false, default: 1
      t.datetime :detected_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :resolved_at
      t.string :resolution_source
      t.string :resolution_note, limit: 500
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :pallastrade_reconciliation_cases, :dedupe_key, unique: true
    add_index :pallastrade_reconciliation_cases, %i[status severity]
    add_index :pallastrade_reconciliation_cases, %i[provider last_seen_at]

    create_table :pallastrade_reconciliation_case_notes do |t|
      t.references :reconciliation_case, null: false, index: true,
                                         foreign_key: { to_table: :pallastrade_reconciliation_cases }
      t.references :author, index: true, foreign_key: { to_table: :pallastrade_admin_users }

      t.text :body, null: false

      t.timestamps
    end
  end
end
