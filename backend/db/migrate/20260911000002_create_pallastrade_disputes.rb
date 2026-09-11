# frozen_string_literal: true

# PRD-20260911-payments-dsp-p7-1 (P7-1) / 冻结依据 PRD-20260911-payments-dsp-p7-0 §5.1
#
# `pallastrade_disputes` — 「非商户发起的资金逆转」的 durable aggregate：
#   卡组织/持卡人/PSP 发起的 dispute / chargeback / inquiry / representment。
#
# 与既有体系的边界（P7-0 B1–B5）：
#   - 不改 CommerceTransaction 状态机（原 txn 保持 completed）
#   - 不复用 Refund/REFUND_SUCCEEDED（Refund ≠ Dispute）
#   - 本表只承载 dispute 事实；财务事实/Journal/对账在 P7-3 另做
#
# 不变量：
#   - UNIQUE(provider, provider_dispute_reference) → 事件幂等键（P7-1 §FR-006）
#   - amount 允许 partial（≤ payment.amount），1 个 payment 可有 N 个 dispute
#   - 无本地锚点（解析不到 Payment）时仍落行：attention_reason 记录原因（事件不丢）
class CreatePallasTradeDisputes < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_disputes do |t|
      t.bigint :store_id
      t.bigint :order_id
      t.bigint :payment_id
      t.bigint :commerce_transaction_id
      t.bigint :payment_combination_id

      t.string :provider, null: false
      t.string :provider_dispute_reference, null: false
      t.string :provider_charge_reference
      t.string :provider_payment_reference

      t.string :kind
      t.string :state, null: false
      t.string :reason
      t.string :network_reason_code

      t.decimal :amount, precision: 12, scale: 2, null: false, default: '0.0'
      t.string :currency
      t.decimal :fee_amount, precision: 12, scale: 2

      t.datetime :evidence_due_at
      t.datetime :evidence_submitted_at
      t.datetime :responded_at
      t.datetime :resolved_at

      t.string :outcome
      # 非空 = 该行需要人工关注（如 unlinked_payment / non_positive_amount），P7-6 Recovery 兜底
      t.string :attention_reason

      t.jsonb :private_metadata
      t.jsonb :public_metadata

      t.timestamps
    end

    add_index :pallastrade_disputes, %i[provider provider_dispute_reference],
              unique: true, name: 'idx_pt_disputes_provider_ref'
    add_index :pallastrade_disputes, :payment_id
    add_index :pallastrade_disputes, :order_id
    add_index :pallastrade_disputes, :store_id
    add_index :pallastrade_disputes, %i[state evidence_due_at]
  end
end
