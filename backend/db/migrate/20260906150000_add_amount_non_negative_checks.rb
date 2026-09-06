# frozen_string_literal: true

# CORE-P5-6（2026-09-06）：首层 DB 金额不变量固化 —— 把已在模型层长期稳定的
# "金额 ≥ 0" 约定升级为可执行 DB CHECK constraint（P5 §21-23 / docs/research/
# RESEARCH-20260906-p5-0-... §8 DB_INVARIANT_GAP_MATRIX 首推第一梯队）。
#
# 范围（纯增量，无行为变化；dev 数据预检 0 负值 / amount_snapshot 0 NULL）：
#   - pallastrade_commerce_transactions.amount            >= 0
#   - pallastrade_payment_splits.authorized/captured/refunded_amount >= 0
#   - pallastrade_transaction_orders.amount_snapshot      >= 0（+ NOT NULL，
#     两个创建点 Transactions::Start / PaymentCombinations::Create 均必填）
#
# 不做（对齐 §23 不过度 DB 化）：状态机、复杂业务规则、reservation active unique
# 的 expires_at 语义（后者需单独设计评审）。
class AddAmountNonNegativeChecks < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :pallastrade_commerce_transactions,
                         'amount >= 0',
                         name: 'pt_commerce_transactions_amount_non_negative'

    add_check_constraint :pallastrade_payment_splits,
                         'authorized_amount >= 0',
                         name: 'pt_payment_splits_authorized_non_negative'
    add_check_constraint :pallastrade_payment_splits,
                         'captured_amount >= 0',
                         name: 'pt_payment_splits_captured_non_negative'
    add_check_constraint :pallastrade_payment_splits,
                         'refunded_amount >= 0',
                         name: 'pt_payment_splits_refunded_non_negative'

    add_check_constraint :pallastrade_transaction_orders,
                         'amount_snapshot >= 0',
                         name: 'pt_transaction_orders_amount_snapshot_non_negative'
    change_column_null :pallastrade_transaction_orders, :amount_snapshot, false
  end

  def down
    remove_check_constraint :pallastrade_transaction_orders,
                            name: 'pt_transaction_orders_amount_snapshot_non_negative'
    change_column_null :pallastrade_transaction_orders, :amount_snapshot, true

    remove_check_constraint :pallastrade_payment_splits,
                            name: 'pt_payment_splits_refunded_non_negative'
    remove_check_constraint :pallastrade_payment_splits,
                            name: 'pt_payment_splits_captured_non_negative'
    remove_check_constraint :pallastrade_payment_splits,
                            name: 'pt_payment_splits_authorized_non_negative'

    remove_check_constraint :pallastrade_commerce_transactions,
                            name: 'pt_commerce_transactions_amount_non_negative'
  end
end
