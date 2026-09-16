# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4 汇率与货币转换）——
# 汇率域 2 张表：
#   * `pallastrade_currency_rates`  —— 多源汇率（manual / provider / third_party + 优先级 + 生效窗口）；
#   * `pallastrade_fx_snapshots`    —— 下单锁汇快照（display_rate + 加点后 effective_rate）+ 结算汇率对比结果。
#
# 铁律：汇率只用于**结算差核算**；不改订单/支付金额、不写资金流水、不调外部汇率 API。
# 与成本域（§70.3 `payment_fee_policies.currency_conversion_percent`）区分：那是**费用**口径，本表是**汇率**口径。
class CreatePallasTradeCurrencyRates < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_currency_rates do |t|
      # store_id 可空 = 全局汇率；非空 = 店铺汇率（店铺级优先于全局）
      t.references :store, null: true, index: true, foreign_key: { to_table: :pallastrade_stores }

      t.string :base_currency, limit: 10, null: false
      t.string :quote_currency, limit: 10, null: false
      t.decimal :rate, precision: 20, scale: 10, null: false
      t.string :source, null: false, default: 'manual'
      # 默认值由模型按来源归一化赋值（provider 30 / third_party 20 / manual 10）
      t.integer :priority, null: false
      t.datetime :effective_from
      t.datetime :effective_until
      t.string :status, null: false, default: 'active'
      t.datetime :revoked_at
      t.string :note
      t.bigint :created_by_id
      # 幂等身份键：SHA256("rate:<store|global>:<base>:<quote>:<source>:<effective_from_iso>")
      t.string :identity_key, limit: 64, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :pallastrade_currency_rates, :identity_key, unique: true, name: 'idx_currency_rates_identity'
    add_index :pallastrade_currency_rates, %i[base_currency quote_currency status],
              name: 'idx_currency_rates_pair_status'
    add_index :pallastrade_currency_rates, %i[store_id status], name: 'idx_currency_rates_store_status'
    add_index :pallastrade_currency_rates, %i[status effective_from], name: 'idx_currency_rates_status_effective'

    create_table :pallastrade_fx_snapshots do |t|
      t.references :store, null: true, index: true, foreign_key: { to_table: :pallastrade_stores }
      t.references :order, null: false, index: true, foreign_key: { to_table: :pallastrade_orders }
      # 结算侧落地后回填（描述性，不做唯一约束）
      t.bigint :payment_id
      t.bigint :currency_rate_id

      t.string :base_currency, limit: 10, null: false
      t.string :quote_currency, limit: 10, null: false
      t.decimal :display_rate, precision: 20, scale: 10, null: false
      t.decimal :up_charge_percent, precision: 6, scale: 4, null: false, default: '0.0'
      t.decimal :effective_rate, precision: 20, scale: 10, null: false
      t.string :rate_source, null: false, default: 'manual'
      t.datetime :locked_at, null: false
      t.string :locked_on, null: false, default: 'order.submitted'

      # 结算对比（结算台账落地后由 Compare 写入）
      t.decimal :settlement_rate, precision: 20, scale: 10
      t.string :settlement_source
      t.string :settlement_currency, limit: 10
      t.decimal :settled_gross_amount, precision: 12, scale: 2
      t.integer :variance_bips
      t.string :variance_status, null: false, default: 'pending'
      t.datetime :compared_at
      t.bigint :reconciliation_case_id
      t.integer :occurrences, null: false, default: 0
      t.jsonb :signals, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    # 一单一种币对只锁一次（幂等：重复投递不产生第二行）
    add_index :pallastrade_fx_snapshots, %i[order_id base_currency quote_currency], unique: true,
                                                                                  name: 'idx_fx_snapshots_order_pair'
    add_index :pallastrade_fx_snapshots, %i[store_id variance_status], name: 'idx_fx_snapshots_store_variance'
    add_index :pallastrade_fx_snapshots, %i[variance_status locked_at], name: 'idx_fx_snapshots_variance_locked'
  end
end
