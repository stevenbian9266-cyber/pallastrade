# This migration comes from pallastrade (originally 20260115120000)
class CreatePallasTradeCustomerGroups < ActiveRecord::Migration[7.0]
  def change
    create_table :pallastrade_customer_groups do |t|
      t.references :store, null: false, index: true
      t.string :name, null: false
      t.text :description
      t.timestamps
      t.datetime :deleted_at
    end

    add_index :pallastrade_customer_groups, [:store_id, :name], unique: true, where: 'deleted_at IS NULL'
    add_index :pallastrade_customer_groups, :deleted_at
  end
end
