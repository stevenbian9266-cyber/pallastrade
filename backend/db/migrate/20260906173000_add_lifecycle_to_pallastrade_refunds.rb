# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-1 (PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation)
#
# Refund durable lifecycle —— 把 PallasTrade::Refund 从 successful-refund-only row
# 升级为 Durable Refund Execution Aggregate：
#   - state: requested/processing/succeeded/failed/ambiguous/manual_review/canceled
#   - ownership（可空，仅可证明时填充）：commerce_transaction / target_order / payment_split
#   - provider_idempotency_key（跨 retry/Recovery 稳定）
#   - 生命周期时间戳 + last_error + attempt_count + lock_version
# 语义冻结见源文档 REV-P6 §54-56（REV-INV-01/02/03/06）。
class AddLifecycleToPallasTradeRefunds < ActiveRecord::Migration[8.1]
  def up
    add_column :pallastrade_refunds, :state, :string, null: false, default: 'requested'
    add_column :pallastrade_refunds, :requested_at, :datetime
    add_column :pallastrade_refunds, :processing_at, :datetime
    add_column :pallastrade_refunds, :succeeded_at, :datetime
    add_column :pallastrade_refunds, :failed_at, :datetime
    add_column :pallastrade_refunds, :ambiguous_at, :datetime
    add_column :pallastrade_refunds, :provider_idempotency_key, :string
    add_column :pallastrade_refunds, :last_error_code, :string
    add_column :pallastrade_refunds, :last_error_message, :string
    add_column :pallastrade_refunds, :attempt_count, :integer, null: false, default: 0
    add_column :pallastrade_refunds, :lock_version, :integer, null: false, default: 0

    # ownership（可空；仅 REV-P6-1 创建时可证明才填充，禁止事后猜填）
    add_reference :pallastrade_refunds, :commerce_transaction,
                  foreign_key: { to_table: :pallastrade_commerce_transactions }, index: true
    add_reference :pallastrade_refunds, :target_order,
                  foreign_key: { to_table: :pallastrade_orders }, index: true
    add_reference :pallastrade_refunds, :payment_split,
                  foreign_key: { to_table: :pallastrade_payment_splits }, index: true

    # provider idempotency key 全局唯一（partial unique）
    add_index :pallastrade_refunds, :provider_idempotency_key,
              unique: true, where: 'provider_idempotency_key IS NOT NULL',
              name: 'idx_refunds_provider_idempotency_key_unique'

    # capacity/scope 查询热路径
    add_index :pallastrade_refunds, %i[payment_id state], name: 'idx_refunds_payment_state'
    add_index :pallastrade_refunds, :state, name: 'idx_refunds_state'
  end

  def down
    remove_index :pallastrade_refunds, name: 'idx_refunds_state'
    remove_index :pallastrade_refunds, name: 'idx_refunds_payment_state'
    remove_index :pallastrade_refunds, name: 'idx_refunds_provider_idempotency_key_unique'
    remove_reference :pallastrade_refunds, :payment_split
    remove_reference :pallastrade_refunds, :target_order
    remove_reference :pallastrade_refunds, :commerce_transaction
    remove_column :pallastrade_refunds, :lock_version
    remove_column :pallastrade_refunds, :attempt_count
    remove_column :pallastrade_refunds, :last_error_message
    remove_column :pallastrade_refunds, :last_error_code
    remove_column :pallastrade_refunds, :ambiguous_at
    remove_column :pallastrade_refunds, :failed_at
    remove_column :pallastrade_refunds, :succeeded_at
    remove_column :pallastrade_refunds, :processing_at
    remove_column :pallastrade_refunds, :requested_at
    remove_column :pallastrade_refunds, :provider_idempotency_key
    remove_column :pallastrade_refunds, :state
  end
end
