class AddAutomaticToSpreeTaxons < ActiveRecord::Migration[6.1]
  def change
    add_column :PALLASTRADE_taxons, :automatic, :boolean, default: false, null: false
  end
end
