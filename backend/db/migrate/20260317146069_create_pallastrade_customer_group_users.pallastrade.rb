# This migration comes from pallastrade (originally 20260115120001)
class CreatePallasTradeCustomerGroupUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :pallastrade_customer_group_users do |t|
      t.references :customer_group, null: false, index: true
      t.references :user, polymorphic: true, null: false, index: true
      t.timestamps
    end

    add_index :pallastrade_customer_group_users,
              [:customer_group_id, :user_id, :user_type],
              unique: true,
              name: 'index_pallastrade_customer_group_users_unique'
  end
end
