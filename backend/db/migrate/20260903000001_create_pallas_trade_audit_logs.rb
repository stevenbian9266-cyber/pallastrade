# frozen_string_literal: true

# P0-6 (2026-09-03): Payment 敏感操作审计表（PRD FR-064）。
#
# 覆盖：Webhook Replay / Manual Payment Repair / Refund / Gateway Credential
# Change 等敏感操作。由 PallasTrade::Audit.record 写入；actor 可为模型（多态）或
# 自由字符串（如 'system'）。before/after 仅存结构化 diff（敏感字段按需脱敏）。
class CreatePallasTradeAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_audit_logs do |t|
      t.string :actor_type
      t.bigint :actor_id
      t.string :actor_label
      t.string :action, null: false
      t.string :resource_type
      t.bigint :resource_id
      t.string :resource_prefixed_id
      t.string :request_id
      t.jsonb :before
      t.jsonb :after
      t.jsonb :metadata
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :pallastrade_audit_logs, [:resource_type, :resource_id]
    add_index :pallastrade_audit_logs, [:actor_type, :actor_id]
    add_index :pallastrade_audit_logs, :action
    add_index :pallastrade_audit_logs, :occurred_at
  end
end
