class AddMissingIndexesOnPallasTradeAdjustments < ActiveRecord::Migration[7.2]
  def change
    add_index :pallastrade_adjustments, :source_type, if_not_exists: true
    add_index :pallastrade_adjustments, :amount, if_not_exists: true
  end
end
