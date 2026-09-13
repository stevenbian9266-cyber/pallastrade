# frozen_string_literal: true

# PRD-20260913-payments-dsp-p7-8 (DSP-P7-8)
#
# `pallastrade_dispute_evidence_submissions` —— 争议**危险操作**（Submit Evidence / Accept Dispute）的不可变回执。
#
# 为什么必须有这张表（而不是塞进 `private_metadata`）：
#   1. **审计强度**：危险操作必须能回答「谁、何时、提交了什么、provider 回了什么」——可查询、可索引、不可改；
#   2. **幂等基准**：同一 payload 重复提交**不得**再次调用 provider（唯一键 `(dispute_id, kind, payload_digest)`）；
#   3. **与账本同源纪律**：append-only；**本表不含任何金额列** —— 资金结果仍由 provider webhook 驱动
#      P7-3 入账 / P7-6 收敛链路，危险操作本身不碰钱。
#
# 纯新增：无既有表修改、无数据回填（历史争议零影响）。
class CreatePallasTradeDisputeEvidenceSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_dispute_evidence_submissions do |t|
      t.references :dispute, null: false, foreign_key: { to_table: :pallastrade_disputes }, index: false
      t.string :kind, null: false
      t.string :payload_digest, null: false
      t.string :provider_reference
      t.string :provider_status
      t.string :actor_type
      t.string :actor_id
      t.string :actor_label
      t.boolean :late, null: false, default: false
      t.string :accepted_reason
      t.jsonb :response_metadata, null: false, default: {}

      t.timestamps
    end

    add_index :pallastrade_dispute_evidence_submissions, %i[dispute_id kind],
              name: 'idx_dispute_ev_sub_disp_kind'
    add_index :pallastrade_dispute_evidence_submissions, %i[dispute_id kind payload_digest],
              unique: true, name: 'idx_dispute_ev_sub_idempotency'
    add_index :pallastrade_dispute_evidence_submissions, :provider_reference,
              name: 'idx_dispute_ev_sub_provider_ref'
  end
end
