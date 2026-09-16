# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片3（PRD-20260916-payments-d14c-dispute-rate-board；业务方案 §71.3 + §72.5）——
# **拒付率预警台账**：每个「店铺 × 卡组织 × 评估日」一行，记录当时观测到的拒付率与阈值位置。
#
# 为什么需要这张表：比率本身是**实时可算的只读指标**，但「什么时候开始逼近阈值」必须可回溯；
# 台账把「不遗漏」（评估即落行）与「不重复」（唯一键 `dedupe_key`）变成**数据层保证**，
# 并让「档位升级」（approaching → breached）只在**同一行**上升级一次（不会每天刷一堆重复告警）。
#
# 只落 `approaching` / `breached`（`ok` / `unconfigured` 不落行，避免噪声）。
#
# 只新增表/索引，不回填、不改既有列。
class CreatePallasTradeDisputeRateAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_dispute_rate_alerts do |t|
      t.bigint :store_id, null: false
      t.string :network, null: false
      t.string :tier, null: false
      t.date :evaluated_on, null: false
      t.integer :window_days, null: false, default: 30

      # 观测值（bps = 万分之一；nil = 不可判定，不用 0 伪装）
      t.integer :count_ratio_bps
      t.integer :amount_ratio_bps
      t.integer :count_threshold_bps
      t.integer :amount_threshold_bps

      # 分母/分子原始观测（可解释性：页面与 CSV 直接读这些值，不再二次计算）
      t.integer :transactions_count, null: false, default: 0
      t.integer :disputes_count, null: false, default: 0
      t.decimal :transactions_amount, precision: 12, scale: 2
      t.decimal :disputes_amount, precision: 12, scale: 2
      t.string :currency

      t.jsonb :triggered_metrics, null: false, default: []
      t.string :dedupe_key, null: false
      t.datetime :detected_at, null: false
      t.datetime :escalated_at
      t.jsonb :metadata

      t.timestamps
    end

    # 幂等：同店 × 同组织 × 同评估日只一行（并发重跑由唯一键兜底）
    add_index :pallastrade_dispute_rate_alerts, :dedupe_key,
              unique: true, name: 'idx_dispute_rate_alerts_dedupe'
    # 后台看板：按店铺 + 档位 + 评估日筛选/计数（同一 scope）
    add_index :pallastrade_dispute_rate_alerts, %i[store_id tier evaluated_on],
              name: 'idx_dispute_rate_alerts_store_tier'
    # 组织维度历史（跨店审计/卡组织复盘）
    add_index :pallastrade_dispute_rate_alerts, %i[network evaluated_on],
              name: 'idx_dispute_rate_alerts_network'
  end
end
