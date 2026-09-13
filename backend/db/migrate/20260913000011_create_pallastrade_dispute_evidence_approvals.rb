# frozen_string_literal: true

# PRD-20260913-payments-…-边界-c-… (DSP-P7-10 B2 / FR-005)
#
# `pallastrade_dispute_evidence_approvals` —— 争议证据**草稿复核**记录（双人复核工作流）。
#
# 为什么独立成表：
#   1. 回执（`…_evidence_submissions`）记录的是**对外动作**；本表记录的是**内部签核**，是提交的**前置条件**；
#   2. **append-only**：签核不可篡改（复核意义在于可追溯，能改就等于没复核）；
#   3. **不含任何金额列**、不参与账本 / 对账 / 库存 / 订单 —— 复核是控制手段，不是资金动作。
#
# 纯新增：无既有表修改、无数据回填（历史争议零影响；开关默认关闭 → 既有提交路径行为不变）。
class CreatePallasTradeDisputeEvidenceApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_dispute_evidence_approvals do |t|
      t.references :dispute, null: false, foreign_key: { to_table: :pallastrade_disputes }, index: false
      t.string :payload_digest, null: false
      t.string :decision, null: false, default: 'approved'
      t.string :actor_type
      t.string :actor_id
      t.string :actor_label
      t.string :requested_by
      t.text :note

      t.timestamps
    end

    add_index :pallastrade_dispute_evidence_approvals, %i[dispute_id payload_digest decision],
              name: 'idx_dispute_ev_appr_lookup'
    add_index :pallastrade_dispute_evidence_approvals, %i[dispute_id payload_digest decision actor_id],
              unique: true, name: 'idx_dispute_ev_appr_unique'
  end
end
