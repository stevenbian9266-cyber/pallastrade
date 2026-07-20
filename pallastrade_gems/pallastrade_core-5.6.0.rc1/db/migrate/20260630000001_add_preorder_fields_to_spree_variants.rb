class AddPreorderFieldsToSpreeVariants < ActiveRecord::Migration[7.2]
  def change
    add_column :PALLASTRADE_variants, :preorderable, :boolean
    add_column :PALLASTRADE_variants, :preorder_ships_at, :datetime
    add_column :PALLASTRADE_variants, :backorder_limit, :integer
  end
end
