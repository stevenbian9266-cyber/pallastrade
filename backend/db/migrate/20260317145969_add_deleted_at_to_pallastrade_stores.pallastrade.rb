# This migration comes from pallastrade (originally 20210920090344)
class AddDeletedAtToPallasTradeStores < ActiveRecord::Migration[5.2]
  def change
    unless column_exists?(:pallastrade_stores, :deleted_at)
      add_column :pallastrade_stores, :deleted_at, :datetime
      add_index :pallastrade_stores, :deleted_at
    end
  end
end
