# frozen_string_literal: true

# PALLAS-CUSTOM: P4 review 批3b-1 (2026-09-06)
# - D1: payments.payment_session_id 加 partial UNIQUE（FR-015「1 session ≤ 1 payment」物理兜底）。
#   先清理历史重复：同一 payment_session 多条 payment → 保留最新，其余置 NULL（旧行仍有
#   response_code 等 PSP 引用，不删）。
# - D4: 删除 orders.payment_combination_id 死列（PaymentGroup 早期设计遗留；全仓 0 代码引用，
#   Order 无关联）。先删 FK + index 再删列。
class HardenPaymentsSessionUniqueAndDropOrdersDeadColumn < ActiveRecord::Migration[8.1]
  def up
    # D1 历史重复清理（幂等：无重复则 0 行受影响）
    execute <<~SQL
      UPDATE pallastrade_payments
      SET payment_session_id = NULL
      WHERE payment_session_id IS NOT NULL
        AND id NOT IN (
          SELECT MAX(id) FROM pallastrade_payments
          WHERE payment_session_id IS NOT NULL
          GROUP BY payment_session_id
        )
    SQL

    remove_index :pallastrade_payments, name: 'index_pallastrade_payments_on_payment_session_id'
    add_index :pallastrade_payments, :payment_session_id, unique: true,
              where: 'payment_session_id IS NOT NULL',
              name: 'idx_pallastrade_payments_session_unique'

    # D4 死列 + FK + index 删除
    remove_foreign_key :pallastrade_orders, :pallastrade_payment_combinations,
                       column: :payment_combination_id
    remove_index :pallastrade_orders, name: 'index_pallastrade_orders_on_payment_combination_id'
    remove_column :pallastrade_orders, :payment_combination_id
  end

  def down
    # D4 恢复
    add_column :pallastrade_orders, :payment_combination_id, :bigint
    add_index :pallastrade_orders, :payment_combination_id,
              name: 'index_pallastrade_orders_on_payment_combination_id'
    add_foreign_key :pallastrade_orders, :pallastrade_payment_combinations,
                    column: :payment_combination_id

    # D1 恢复普通索引
    remove_index :pallastrade_payments, name: 'idx_pallastrade_payments_session_unique'
    add_index :pallastrade_payments, :payment_session_id,
              name: 'index_pallastrade_payments_on_payment_session_id'
  end
end
