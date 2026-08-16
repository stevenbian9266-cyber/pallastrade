# frozen_string_literal: true

# PALLAS-CUSTOM: 可视化菜单配置覆盖层（2026-08-16）
# store_id 可空：NULL = 全局默认配置；非 NULL = 店铺覆盖配置。
# item_type: default（覆盖现有导航项）/ custom（自定义菜单项）
class CreatePallasTradeMenuConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_menu_configs do |t|
      t.references :store, null: true, foreign_key: { to_table: :pallastrade_stores }
      t.string :item_type, null: false, default: 'default'
      t.string :nav_key, null: false
      t.boolean :visible, null: true
      t.string :label, null: true
      t.integer :position, null: true
      t.string :icon, null: true
      t.string :url, null: true
      t.string :parent_key, null: true
      t.boolean :open_in_new_tab, null: false, default: false
      t.timestamps
    end

    # 全局（store_id IS NULL）每 nav_key 唯一
    add_index :pallastrade_menu_configs, :nav_key, unique: true,
              name: 'index_pallastrade_menu_configs_on_key_global', where: 'store_id IS NULL'
    # 店铺覆盖（store_id 非 NULL）每 (store, nav_key) 唯一
    add_index :pallastrade_menu_configs, [:store_id, :nav_key], unique: true,
              name: 'index_pallastrade_menu_configs_on_store_and_key', where: 'store_id IS NOT NULL'
  end
end
