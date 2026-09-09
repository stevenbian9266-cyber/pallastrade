# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8j (PRD-20260909-payments-rev-p6-8j-ordercancellation-state-machine; 源 REV-P6 §34)
#
# OrderCancellation durable-intent 生命周期（REV-P6-0 DB audit 落地）：
#   - 新增 state 列（default 'requested'，indexed）——OrderCancellation 从无状态普通行升级为带
#     生命周期（requested/applied/failed/recovery_required/manual_review）的 durable 取消意图。
#   - 存量行回填 'applied'：历史 OC 均由 Orders::Cancel 成功应用（订单已取消 + durable refunds 已建），
#     语义等于 applied。幂等：任何新加后再次 migrate 无需处理（单次迁移）。
class AddStateToPallasTradeOrderCancellations < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_order_cancellations, :state, :string, default: 'requested', null: false
    add_index :pallastrade_order_cancellations, :state, name: 'index_pt_order_cancellations_on_state'

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE pallastrade_order_cancellations
             SET state = 'applied'
           WHERE state = 'requested'
        SQL
      end
    end
  end
end
