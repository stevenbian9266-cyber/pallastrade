# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists；业务方案 §72.3 名单 / §72.2 决策留痕底座 / §74.1 表名规划）——
# 风控名单台账（denylist / allowlist）：
#   * 一行 = 一个「主体值」（邮箱 / BIN / IP / 卡指纹 / 客户 / 地址 / 国家），
#     幂等靠唯一键 (list_type, subject_type, value_hash)（value_hash = 归一化后的 SHA256）。
#   * 到期即失效（status='active' AND (expires_at IS NULL OR expires_at > now)）；撤销走 status='revoked'（**不物理删**，保留审计）。
#   * 铁律：名单是**运营事实**，本身不阻断任何流程（决策由 `Risk::Assess` 产出，处置留给后续切片）。
class CreatePallasTradePaymentRiskLists < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_payment_risk_lists do |t|
      # store_id 可空 = 全局名单（所有店铺生效）；非空 = 店铺名单（店铺隔离硬边界）
      t.references :store, null: true, index: true, foreign_key: { to_table: :pallastrade_stores }

      t.string :list_type, null: false
      t.string :subject_type, null: false
      t.string :value, limit: 500, null: false
      t.string :value_hash, limit: 64, null: false
      t.string :status, null: false, default: 'active'
      t.datetime :expires_at
      t.text :reason
      t.bigint :added_by_id
      t.string :added_by_type
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :pallastrade_payment_risk_lists, %i[list_type subject_type value_hash], unique: true,
                                                                                    name: 'idx_risk_lists_identity'
    add_index :pallastrade_payment_risk_lists, %i[store_id subject_type status],
              name: 'idx_risk_lists_store_subject'
    add_index :pallastrade_payment_risk_lists, %i[status expires_at]

    # 决策留痕：每次评估一行（订单页/后续复核队列的唯一数据源）
    create_table :pallastrade_payment_risk_assessments do |t|
      t.references :order, null: true, index: true, foreign_key: { to_table: :pallastrade_orders }
      t.references :store, null: true, index: true, foreign_key: { to_table: :pallastrade_stores }

      t.string :decision, null: false
      t.jsonb :matched_entry_ids, null: false, default: []
      t.jsonb :signals, null: false, default: {}
      t.datetime :evaluated_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    # 幂等键：同一订单同一秒只落一行（订阅者重复投递不产生第二行）
    add_index :pallastrade_payment_risk_assessments, %i[order_id evaluated_at], unique: true,
                                                                               name: 'idx_risk_assessments_order_time'
    add_index :pallastrade_payment_risk_assessments, %i[store_id decision],
              name: 'idx_risk_assessments_store_decision'
  end
end
