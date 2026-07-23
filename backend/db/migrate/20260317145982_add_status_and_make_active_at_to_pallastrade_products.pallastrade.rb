# This migration comes from pallastrade (originally 20220103082046)
class AddStatusAndMakeActiveAtToPallasTradeProducts < ActiveRecord::Migration[5.2]
  def change
    add_column :pallastrade_products, :status, :string, null: false, default: 'draft'
    add_index :pallastrade_products, :status
    add_index :pallastrade_products, %i[status deleted_at]
  end
end
