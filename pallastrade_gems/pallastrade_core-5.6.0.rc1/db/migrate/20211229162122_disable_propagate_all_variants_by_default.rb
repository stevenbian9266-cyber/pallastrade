class DisablePropagateAllVariantsByDefault < ActiveRecord::Migration[5.2]
  def change
    change_column_default :PALLASTRADE_stock_locations, :propagate_all_variants, false
  end
end
