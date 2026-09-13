# frozen_string_literal: true

# PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-… (DSP-P7-10 B1)
#
# `pallastrade_dispute_evidence_assets` —— 争议**证据素材库**（运营可复用素材）。
#
# 为什么独立成表：
#   1. **与回执分离**：回执（`pallastrade_dispute_evidence_submissions`）是**对外动作**的不可变留痕；
#      素材库是**我方知识**（说明文本 / 条款截图 / 物流凭证），生命周期与回执完全不同；
#   2. **零资金语义**：本表**不含任何金额列**、不参与账本 / 对账 / 库存 / 订单；
#   3. **只读引用**：引用素材只产生普通值（见 `Disputes::EvidenceAssets#insert`），提交仍走
#      `Disputes::SubmitEvidence`（危险操作三件套）。
#
# 纯新增：无既有表修改、无数据回填（历史争议零影响）。
class CreatePallasTradeDisputeEvidenceAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_dispute_evidence_assets do |t|
      t.references :store, null: true, foreign_key: { to_table: :pallastrade_stores }, index: false
      t.string :name, null: false
      t.string :kind, null: false, default: 'text'
      t.string :evidence_key
      t.string :reason_code
      t.text :body
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.string :created_by

      t.timestamps
    end

    add_index :pallastrade_dispute_evidence_assets, %i[store_id active],
              name: 'idx_dispute_ev_assets_store_active'
    add_index :pallastrade_dispute_evidence_assets, %i[store_id name],
              unique: true, name: 'idx_dispute_ev_assets_store_name'
    add_index :pallastrade_dispute_evidence_assets, %i[store_id reason_code],
              name: 'idx_dispute_ev_assets_store_reason'
  end
end
