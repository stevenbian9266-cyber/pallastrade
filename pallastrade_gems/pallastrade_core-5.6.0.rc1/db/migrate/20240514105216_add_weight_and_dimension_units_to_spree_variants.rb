class AddWeightAndDimensionUnitsToSpreeVariants < ActiveRecord::Migration[6.1]
  def change
    add_column :PALLASTRADE_variants, :weight_unit, :string, if_not_exists: true
    add_column :PALLASTRADE_variants, :dimensions_unit, :string, if_not_exists: true
  end
end
