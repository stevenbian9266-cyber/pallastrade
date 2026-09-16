# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片1（PRD-20260916-payments-d14-refund-approval；业务方案 §71.1）——
# 退款审批（双人复核）持久化：
#   * pallastrade_refund_approvals：超阈值退款的待批记录（pending → approved / rejected）；
#   * pallastrade_refunds.request_key：请求级幂等键（防重复退款）。
#
# 只新增表/列/索引，不回填、不改既有列（既有退款行为零变化）。
class CreatePallasTradeRefundApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_refund_approvals do |t|
      t.bigint :store_id, null: false
      t.bigint :refund_id, null: false
      t.string :status, null: false, default: 'pending'
      t.decimal :amount, precision: 10, scale: 2, null: false, default: '0.0'
      t.string :currency
      t.bigint :requester_id
      t.bigint :approver_id
      t.datetime :decided_at
      t.text :note
      t.jsonb :policy_snapshot
      t.jsonb :metadata
      t.timestamps
    end

    # 一笔退款最多一条审批记录（幂等的数据层兜底）
    add_index :pallastrade_refund_approvals, :refund_id, unique: true
    # 工作台主查询：按店铺 + 状态（默认 pending）
    add_index :pallastrade_refund_approvals, %i[store_id status]
    add_index :pallastrade_refund_approvals, %i[store_id created_at]

    # 请求级幂等键：同一 key 重复提交 → 复用既有退款，不产生第二笔（防重复退款）
    add_column :pallastrade_refunds, :request_key, :string
    add_index :pallastrade_refunds, :request_key,
              unique: true, where: 'request_key IS NOT NULL',
              name: 'idx_refunds_request_key_unique'
  end
end
