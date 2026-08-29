# frozen_string_literal: true

# 订单流程标准电商改造 P1（2026-08-30）：购物车与订单分表。
# 新建 pallastrade_carts + pallastrade_cart_items 表承载购物车会话。
# 设计见 docs/design/order-flow-redesign.md §1 与
# docs/prd/checkout/PRD-20260829-...订单流程标准电商改造....md §6.1。
class CreatePallasTradeCarts < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_carts do |t|
      t.string   :token, null: false
      t.bigint   :user_id
      t.bigint   :store_id, null: false
      t.string   :currency, null: false, default: 'USD'
      t.string   :locale, null: false, default: 'en'
      t.string   :status, null: false, default: 'active'
      t.string   :email
      t.bigint   :shipping_address_id
      t.bigint   :billing_address_id
      t.string   :customer_note
      t.datetime :expires_at
      t.jsonb    :public_metadata, default: {}
      t.jsonb    :private_metadata, default: {}
      t.datetime :converted_at
      t.datetime :last_activity_at
      t.timestamps
    end

    add_index :pallastrade_carts, :token, unique: true
    add_index :pallastrade_carts, :store_id
    add_index :pallastrade_carts, :user_id
    add_index :pallastrade_carts, :status

    create_table :pallastrade_cart_items do |t|
      t.bigint  :cart_id, null: false
      t.bigint  :variant_id, null: false
      t.integer :quantity, null: false, default: 1
      t.boolean :selected, null: false, default: true
      t.jsonb   :metadata, default: {}
      t.timestamps
    end

    add_index :pallastrade_cart_items, :cart_id
    add_index :pallastrade_cart_items, :variant_id
    add_index :pallastrade_cart_items, [:cart_id, :variant_id], unique: true
  end
end
