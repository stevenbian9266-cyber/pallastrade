# This migration comes from pallastrade (originally 20241128103947)
class AddAutomaticToPallasTradeTaxons < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_taxons, :automatic, :boolean, default: false, null: false
  end
end
