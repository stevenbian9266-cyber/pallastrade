# This migration comes from pallastrade (originally 20260630000001)
class AddPreorderFieldsToPallasTradeVariants < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_variants, :preorderable, :boolean
    add_column :pallastrade_variants, :preorder_ships_at, :datetime
    add_column :pallastrade_variants, :backorder_limit, :integer
  end
end
