# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-1 (PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation)
#
# 历史 Refund backfill（FR-R61-601/602）：
#   - 现有持久化 Refund 行均为"创建即成功"（旧 after_create perform! 成功才落库；
#     validates transaction_id on: update 兜底）→ transaction_id 存在即可安全 state='succeeded'。
#   - 例外：transaction_id 为 NULL 的行（仅手工/异常造数）→ state='manual_review'（不猜，AC-6029）。
#   - ownership backfill：commerce_transaction_id 仅当可证明（payment → payment_session /
#     payment_combination → commerce_transaction）时填充；不可证明保持 NULL（不猜，FR-R61-602）。
class BackfillRefundLifecycle < ActiveRecord::Migration[8.1]
  def up
    # dry-run 计数（部署日志留痕；幂等可重跑）
    total = execute('SELECT COUNT(*) FROM pallastrade_refunds').first['count'].to_i
    succeeded_target =
      execute("SELECT COUNT(*) FROM pallastrade_refunds WHERE transaction_id IS NOT NULL").first['count'].to_i
    review_target =
      execute("SELECT COUNT(*) FROM pallastrade_refunds WHERE transaction_id IS NULL").first['count'].to_i
    Rails.logger.info(
      "[BackfillRefundLifecycle] refunds total=#{total} ->succeeded=#{succeeded_target} ->manual_review=#{review_target}"
    )

    # 1) 成功行 → succeeded
    execute <<~SQL
      UPDATE pallastrade_refunds
         SET state = 'succeeded',
             succeeded_at = COALESCE(succeeded_at, updated_at)
       WHERE transaction_id IS NOT NULL
    SQL

    # 2) 无 transaction_id 例外行 → manual_review（不可证明成功，不猜）
    execute <<~SQL
      UPDATE pallastrade_refunds
         SET state = 'manual_review'
       WHERE transaction_id IS NULL
    SQL

    # 3) ownership backfill（可证明才填）：payment → payment_session → commerce_transaction
    execute <<~SQL
      UPDATE pallastrade_refunds r
         SET commerce_transaction_id = ps.transaction_id
        FROM pallastrade_payments p
        LEFT JOIN pallastrade_payment_sessions ps ON ps.id = p.payment_session_id
       WHERE r.payment_id = p.id
         AND r.commerce_transaction_id IS NULL
         AND ps.transaction_id IS NOT NULL
    SQL

    # payment → payment_combination → commerce_transaction（组合支付）
    execute <<~SQL
      UPDATE pallastrade_refunds r
         SET commerce_transaction_id = txn.id
        FROM pallastrade_payments p
        JOIN pallastrade_payment_combinations pc ON pc.id = p.payment_combination_id
        JOIN pallastrade_commerce_transactions txn ON txn.payment_combination_id = pc.id
       WHERE r.payment_id = p.id
         AND r.commerce_transaction_id IS NULL
         AND p.payment_combination_id IS NOT NULL
    SQL
  end

  def down
    # 数据单向迁移（state 语义无法安全还原），仅回滚为兼容旧代码的默认态。
    execute <<~SQL
      UPDATE pallastrade_refunds SET state = 'requested'
    SQL
  end
end
