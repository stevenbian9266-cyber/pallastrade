# This migration comes from pallastrade (originally 20240725124530)
class AddRefunderToPallasTradeRefunds < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_refunds, :refunder_id, :bigint, if_not_exists: true
    add_index :pallastrade_refunds, :refunder_id, if_not_exists: true
  end
end
