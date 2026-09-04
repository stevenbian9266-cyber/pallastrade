# frozen_string_literal: true

# PALLAS-CUSTOM: CHK-P1-2 (PRD-20260903-checkout-chk-p1-1 §12) —— Order Checkout 版本/过期能力。
#
# 说明：
#   * lock_version：AR 乐观锁列（默认列名），防并发 checkout mutation 互相覆盖；
#     与 state_machines 自带的 state_lock_version（state 转换锁）语义不同、互不冲突。
#   * price_version：影响金额输入的确定性指纹（由 OrderCheckout::Recalculate 计算写入）。
#     PRD 禁止用 public_metadata / updated_at.to_i 冒充 —— 故用正式列。
#   * checkout_expires_at：当前 checkout 商业报价有效期（非取消/abandoned；弃单走 last_activity_at）。
class AddCheckoutVersioningToPallasTradeOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_orders, :lock_version, :integer, default: 0, null: false
    add_column :pallastrade_orders, :price_version, :string
    add_column :pallastrade_orders, :checkout_expires_at, :datetime
  end
end
