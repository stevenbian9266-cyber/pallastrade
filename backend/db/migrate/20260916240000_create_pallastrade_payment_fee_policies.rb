# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片3（PRD-20260916-payments-d13c-fee-cost-report；业务方案 §70.3 费率模型 / §74.1 表名规划）——
# 支付费率策略（rate card）：百分比费 + 固定费 + 跨境费 + 货币转换费 + 平台费。
#
#   * 一条策略 = 一个「适用范围」（`scope_type` + `scope_id`）× 条件（币种 / 卡类型 / 地区）× 生效窗口。
#   * 解析优先级 `method > provider > store > global`（同优先级取 `effective_from` 更晚者，再取 id 更大者）。
#   * `min_fee` / `max_fee` 对**费率类分量之和**（百分比 + 平台 + 跨境%）保底封顶；固定费不参与保底封顶。
#   * 铁律：费率是**只读核算的输入** —— 本表不参与任何资金流、不阻断支付、不调 provider。
#
# 入口（option）身份沿用 D1/D8/D16 的**读模型**（`PaymentMethod` × `method_key`）：
# 逐笔支付未持久化所选 option，故 `scope_type = 'method'` 的 `scope_id` 是 method_key 字符串（如 `card` / `apple_pay`）。
class CreatePallasTradePaymentFeePolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_payment_fee_policies do |t|
      # store_id 可空 = 全局策略（所有店铺生效）；非空 = 店铺策略（店铺隔离硬边界）
      t.references :store, null: true, index: true, foreign_key: { to_table: :pallastrade_stores }

      t.string :name, null: false
      t.string :scope_type, null: false, default: 'global'
      # provider → payment_method_id；method → method_key（入口）；global / store → NULL（校验强制）
      t.string :scope_id

      # 条件（空 = 全部）
      t.string :currency, limit: 10
      t.string :card_type, limit: 32
      t.string :region, limit: 8

      # 费率分量
      t.decimal :percent_fee, precision: 6, scale: 4, default: '0.0', null: false
      t.decimal :fixed_fee, precision: 12, scale: 2, default: '0.0', null: false
      t.decimal :cross_border_percent, precision: 6, scale: 4, default: '0.0', null: false
      t.decimal :cross_border_fixed, precision: 12, scale: 2, default: '0.0', null: false
      t.decimal :currency_conversion_percent, precision: 6, scale: 4, default: '0.0', null: false
      t.decimal :platform_percent, precision: 6, scale: 4, default: '0.0', null: false

      # 保底 / 封顶（对费率类分量之和；空 = 不限制）
      t.decimal :min_fee, precision: 12, scale: 2
      t.decimal :max_fee, precision: 12, scale: 2

      # 跨境 / 货币转换的判定基准（空 = 本地无法判定 → **不计费**并留痕）
      t.string :home_country, limit: 8
      t.string :settlement_currency, limit: 10

      t.datetime :effective_from
      t.datetime :effective_until
      t.string :status, null: false, default: 'active'
      t.datetime :revoked_at
      t.bigint :created_by_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    # §74.1 命名规划要求：按适用范围检索
    add_index :pallastrade_payment_fee_policies, %i[scope_type scope_id], name: 'idx_fee_policies_scope'
    add_index :pallastrade_payment_fee_policies, %i[store_id status], name: 'idx_fee_policies_store_status'
    add_index :pallastrade_payment_fee_policies, %i[status effective_from], name: 'idx_fee_policies_status_effective'
  end
end
