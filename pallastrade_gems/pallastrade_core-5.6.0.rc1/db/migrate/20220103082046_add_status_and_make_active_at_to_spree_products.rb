class AddStatusAndMakeActiveAtToSpreeProducts < ActiveRecord::Migration[5.2]
  def change
    add_column :PALLASTRADE_products, :status, :string, null: false, default: 'draft'
    add_index :pallastrade_products, :status
    add_index :pallastrade_products, %i[status deleted_at]
  end
end
