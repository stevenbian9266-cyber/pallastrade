# frozen_string_literal: true

# P0-2 (2026-09-02): Webhook Event Store —— 每个 webhook 事件的数据库事实记录。
#
# 目的（PRD FR-020..026）：
#   - 事件落库（验签后的原始 provider event payload）
#   - DB 级去重：UNIQUE(provider, provider_event_id)
#   - 失败可见 / 可重试 / 可重放（Replay 走原事件）
#   - attempt_count = HandleWebhook 实际开始执行次数
#
# 说明：除 PRD 字段外，额外加 payment_session_id / action 两列——
#   - payment_session_id：该事件关联的本地 PaymentSession（Replay/Trace 定位用）
#   - action：gateway 归一后的动作（captured/authorized/failed/canceled），
#     落库时冗余保存以便 Replay 不需重新解析 provider payload
class CreatePallasTradePaymentWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_payment_webhook_events do |t|
      t.string :provider, null: false
      t.bigint :payment_method_id, null: false
      t.string :provider_event_id, null: false
      t.string :event_type
      t.datetime :provider_created_at
      t.string :action
      t.bigint :payment_session_id
      t.jsonb :payload
      t.string :status, null: false, default: 'received'
      t.integer :attempt_count, null: false, default: 0
      t.datetime :received_at
      t.datetime :processing_at
      t.datetime :processed_at
      t.string :last_error_class
      t.string :last_error_message
      t.timestamps
    end

    add_index :pallastrade_payment_webhook_events,
              [:provider, :provider_event_id],
              unique: true,
              name: 'index_pallastrade_payment_webhook_events_on_provider_event'
    add_index :pallastrade_payment_webhook_events,
              [:payment_method_id, :status]
    add_index :pallastrade_payment_webhook_events,
              [:payment_session_id],
              name: 'index_pt_payment_webhook_events_on_payment_session_id'
  end
end
