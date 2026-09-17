# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片2（PRD-20260917-payments-d15b-risk-rules；业务方案 §72.2）——
# **风控规则集 + 不可变版本**：两表。
#
# 为什么需要这两张表：规则引擎（P8 `PallasTrade::Risk`）此前是**代码注册式**
# （`Risk.rules << RuleClass`，阈值散落在 preferences / Config）——
# 改规则 = 改代码 + 重启，既无版本、也无法回滚，更谈不上按流量灰度。
# 业务方案 §72.2 要求「每次变更生成版本（可回滚）+ 灰度（按流量百分比）」，
# 因此把「规则内容」从代码搬到数据层：
#   * `rule_sets`   = 稳定的作用域容器（全局 / 店铺），持有「生效版 + 金丝雀版 + 灰度百分比」；
#   * `rule_versions` = 版本快照（**发布后不可变**），回滚 = 以历史版本内容**生成新版本**并生效。
#
# 作用域口径与名单（D15 切片1 `pallastrade_payment_risk_lists`）一致：`store_id` 可空 = 全局。
# 唯一性用 **partial unique index**（Postgres 唯一索引对 NULL 不去重）：
#   * 全局：`code` 唯一（`WHERE store_id IS NULL`）
#   * 店铺：`(store_id, code)` 唯一（`WHERE store_id IS NOT NULL`）
#
# 只新增表/索引，不回填、不改既有列。
class CreatePallasTradeRiskRuleSetsAndVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_risk_rule_sets do |t|
      # NULL = 全局规则集（对所有店铺生效）；非空 = 店铺规则集（更具体，优先）
      t.bigint :store_id
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: 'active'

      # 生效版本（稳定流量）与金丝雀版本（灰度流量）；版本表见下
      t.integer :active_version_id
      t.integer :canary_version_id
      # 灰度百分比 0–100（按订单维度确定性分桶）
      t.integer :canary_percent, null: false, default: 0

      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :pallastrade_risk_rule_sets, :code,
              unique: true, where: 'store_id IS NULL', name: 'idx_risk_rule_sets_global_code'
    add_index :pallastrade_risk_rule_sets, %i[store_id code],
              unique: true, where: 'store_id IS NOT NULL', name: 'idx_risk_rule_sets_store_code'
    add_index :pallastrade_risk_rule_sets, %i[store_id status], name: 'idx_risk_rule_sets_store_status'

    create_table :pallastrade_risk_rule_versions do |t|
      t.bigint :rule_set_id, null: false
      # 每集从 1 单调递增（唯一键保证不重号）
      t.integer :version, null: false
      # draft / published / archived
      t.string :state, null: false, default: 'draft'
      # 规则快照：[{ code, priority, conditions, action, note }]（发布后不可改写）
      t.jsonb :rules, null: false, default: []
      t.text :reason
      # 回滚来源版本号 + 是否回滚产生（可回溯「这一版是谁的内容」）
      t.integer :source_version
      t.boolean :rolled_back, null: false, default: false
      t.string :created_by_type
      t.bigint :created_by_id
      t.datetime :published_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :pallastrade_risk_rule_versions, %i[rule_set_id version],
              unique: true, name: 'idx_risk_rule_versions_set_version'
    add_index :pallastrade_risk_rule_versions, %i[rule_set_id state], name: 'idx_risk_rule_versions_set_state'
    add_index :pallastrade_risk_rule_versions, %i[created_by_type created_by_id],
              name: 'idx_risk_rule_versions_creator'
  end
end
