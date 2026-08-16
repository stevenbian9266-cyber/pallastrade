# frozen_string_literal: true

# PALLAS-CUSTOM: 角色权限（菜单/功能/数据/set）——后台可视化权限体系（2026-08-16）
# permission_type:
#   set      → 引用权限集类（permission_set），保留复杂块逻辑（SuperUser/DefaultCustomer 迁移）
#   function → 资源 × 操作（resource + action: read/create/update/destroy/export/manage）
#   menu     → 导航项可见性（nav_key + allowed）
#   data     → 数据范围（resource + scope: all/self/store/channel/custom）
class CreatePallasTradeRolePermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_role_permissions do |t|
      t.references :role, null: false, foreign_key: { to_table: :pallastrade_roles }
      t.string :permission_type, null: false, default: 'function'
      t.string :permission_set, null: true
      t.string :nav_key, null: true
      t.string :resource, null: true
      t.string :action, null: true
      t.boolean :allowed, null: false, default: true
      t.string :scope, null: true
      t.string :scope_value, null: true
      t.jsonb :custom_condition, null: true
      t.timestamps
    end

    add_index :pallastrade_role_permissions, [:role_id, :permission_type],
              name: 'index_pallastrade_role_permissions_on_role_and_type'
    add_index :pallastrade_role_permissions, [:role_id, :resource, :action],
              name: 'index_pallastrade_role_permissions_on_role_res_action'
  end
end
