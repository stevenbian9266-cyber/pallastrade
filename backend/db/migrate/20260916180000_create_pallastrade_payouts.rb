# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片2（PRD-20260916-payments-d13b-payout-ledger；业务方案 §70.2）——
# 结算（Payout）台账：provider 结算报表导入后的**批次主表**。
#   * 一行 = 一个 provider payout（批次/账户结算），状态：in_transit / settled / difference。
#   * 铁律：台账是**对账事实**，绝不生成资金日志记账、绝不触发资金动作（§70.1 边界沿用）。
class CreatePallasTradePayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_payouts do |t|
      t.references :store, null: false, index: true, foreign_key: { to_table: :pallastrade_stores }

      t.string :provider, null: false
      t.string :reference, null: false
      t.string :status, null: false, default: 'in_transit'
      t.string :currency, limit: 10
      t.decimal :gross_total, precision: 12, scale: 2, null: false, default: 0
      t.decimal :fee_total, precision: 12, scale: 2, null: false, default: 0
      t.decimal :net_total, precision: 12, scale: 2, null: false, default: 0
      t.date :period_start
      t.date :period_end
      t.datetime :settled_at
      t.datetime :imported_at, null: false
      t.string :import_source
      t.jsonb :metadata, null: false, default: {}
      t.string :last_error, limit: 500

      t.timestamps
    end

    add_index :pallastrade_payouts, %i[store_id provider reference], unique: true
    add_index :pallastrade_payouts, %i[store_id status]

    create_table :pallastrade_payout_lines do |t|
      t.references :payout, null: false, index: true, foreign_key: { to_table: :pallastrade_payouts }
      t.references :payment, index: true, foreign_key: { to_table: :pallastrade_payments }
      t.references :refund, index: true, foreign_key: { to_table: :pallastrade_refunds }

      t.string :kind, null: false
      t.string :provider_reference, null: false
      t.string :currency, limit: 10
      t.decimal :gross_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :fee_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :net_amount, precision: 12, scale: 2, null: false, default: 0
      t.string :match_status, null: false, default: 'pending'
      t.jsonb :match_details, null: false, default: {}
      t.datetime :matched_at
      t.jsonb :raw, null: false, default: {}

      t.timestamps
    end

    add_index :pallastrade_payout_lines, %i[payout_id provider_reference kind], unique: true,
                                                                               name: 'idx_pt_payout_lines_identity'
    add_index :pallastrade_payout_lines, :match_status
  end
end
