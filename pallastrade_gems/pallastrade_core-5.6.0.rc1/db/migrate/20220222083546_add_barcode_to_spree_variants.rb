class AddBarcodeToSpreeVariants < ActiveRecord::Migration[5.2]
  def change
    add_column :PALLASTRADE_variants, :barcode, :string
    add_index :pallastrade_variants, :barcode
  end
end
