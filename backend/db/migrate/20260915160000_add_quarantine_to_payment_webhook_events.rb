# frozen_string_literal: true

# PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance 切片1）——
# 入站 webhook 事件的「隔离」语义（业务方案 §69「动作：加入死信 / 隔离（忽略未知事件）」）。
# additive：既有 received/processing/processed/failed 四态语义不变；隔离事件保留留痕、
# 不参与处理（`replayable?` = false），可经后台「解除隔离」复位为 failed 后人工处置。
class AddQuarantineToPaymentWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_payment_webhook_events, :quarantined_at, :datetime
    add_column :pallastrade_payment_webhook_events, :quarantine_reason, :string, limit: 500
  end
end
