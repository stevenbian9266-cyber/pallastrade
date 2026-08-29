# frozen_string_literal: true

# 订单流程标准电商改造 P1（2026-08-30）：购物车增加物流方式选择列。
# 订单确认阶段用户选择配送方式，提交订单时映射到 Order 的 shipments shipping rate。
class AddShippingMethodToPallasTradeCarts < ActiveRecord::Migration[8.1]
  def change
    add_reference :pallastrade_carts, :shipping_method, null: true,
                 foreign_key: { to_table: :pallastrade_shipping_methods }
  end
end
