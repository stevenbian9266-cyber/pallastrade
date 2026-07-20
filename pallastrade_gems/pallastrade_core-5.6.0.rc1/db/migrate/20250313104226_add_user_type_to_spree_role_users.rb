class AddUserTypeToSpreeRoleUsers < ActiveRecord::Migration[6.1]
  def up
    unless column_exists?(:PALLASTRADE_role_users, :user_type)
      add_column :PALLASTRADE_role_users, :user_type, :string
      add_index :pallastrade_role_users, :user_type

      user_class_name = PallasTrade.admin_user_class.to_s
      PallasTrade::RoleUser.where(user_type: nil).update_all(user_type: user_class_name)

      change_column_null :PALLASTRADE_role_users, :user_type, false
    end
  end

  def down
    remove_index :PALLASTRADE_role_users, :user_type, if_exists: true
    remove_column :PALLASTRADE_role_users, :user_type, if_exists: true
  end
end
