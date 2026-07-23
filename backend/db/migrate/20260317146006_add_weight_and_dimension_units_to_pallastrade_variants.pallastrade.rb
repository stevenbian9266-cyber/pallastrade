# This migration comes from pallastrade (originally 20240514105216)
class AddWeightAndDimensionUnitsToPallasTradeVariants < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_variants, :weight_unit, :string, if_not_exists: true
    add_column :pallastrade_variants, :dimensions_unit, :string, if_not_exists: true
  end
end
