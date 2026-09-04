# frozen_string_literal: true

# PALLAS-CUSTOM: CHK-P1-2 (PRD-20260903-checkout-chk-p1-1 §12) —— 版本列调整。
#
# 背景：Order 的 AR locking_column 已被 state_machines 设为 state_lock_version（state 转换锁），
# 新增 lock_version 不参与乐观锁。改用显式 checkout_version（整数自增），由 OrderCheckout
# mutation/recalc/refresh 统一维护 —— 代表"checkout 数据已迭代版本"（内容/金额变更后递增）。
# 移除多余 lock_version 列。
class FixCheckoutVersioningOnPallasTradeOrders < ActiveRecord::Migration[8.1]
  def up
    remove_column :pallastrade_orders, :lock_version if column_exists?(:pallastrade_orders, :lock_version)
    add_column :pallastrade_orders, :checkout_version, :integer, default: 0, null: false
  end

  def down
    remove_column :pallastrade_orders, :checkout_version
    add_column :pallastrade_orders, :lock_version, :integer, default: 0, null: false
  end
end
