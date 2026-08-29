# frozen_string_literal: true

# 订单流程标准电商改造 P1（2026-08-30）：orders 增加来源购物车 FK + 提交时间戳。
# cart_id 可空——存量订单/Admin 代下单/Buy Now 直下单无来源购物车。
# 语义见 PRD §6.1.3。
class AddCartToPallasTradeOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :pallastrade_orders, :cart, null: true,
                 foreign_key: { to_table: :pallastrade_carts }
    add_column :pallastrade_orders, :submitted_at, :datetime
  end
end
