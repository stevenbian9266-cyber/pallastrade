# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片2（PRD-20260916-payments-d14b-dispute-deadlines；业务方案 §71.2）——
# 争议证据期限的**分档提醒台账**：每个争议 × 每个档位一行（T-3 / T-1 / 超期）。
#
# 为什么需要这张表：既有 DSP-P7-5 扫描是只读的、每轮 sweeper 都重复发同一档告警（噪音且无法回答
# 「这一档提醒过没有」）。台账把「不遗漏」（达到档位即落行）与「不重复」（唯一键）变成**数据层保证**。
#
# 只新增表/索引，不回填、不改既有列。
class CreatePallasTradeDisputeDeadlineAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_dispute_deadline_alerts do |t|
      t.bigint :store_id
      t.bigint :dispute_id, null: false
      t.string :tier, null: false
      t.datetime :alerted_at, null: false
      t.datetime :evidence_due_at
      t.decimal :hours_remaining, precision: 10, scale: 2
      t.jsonb :metadata
      t.timestamps
    end

    # 幂等：同一争议同一档位只提醒一次（并发重跑由唯一键兜底）
    add_index :pallastrade_dispute_deadline_alerts, %i[dispute_id tier],
              unique: true, name: 'idx_dispute_deadline_alerts_identity'
    # 后台看板/运营查询：按店铺 + 提醒时间倒序
    add_index :pallastrade_dispute_deadline_alerts, %i[store_id alerted_at]
  end
end
