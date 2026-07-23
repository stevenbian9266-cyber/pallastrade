# This migration comes from pallastrade (originally 20240822163534)
class AddPrettyNameToPallasTradeTaxons < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_taxons, :pretty_name, :string, null: true, if_not_exists: true
    add_index :pallastrade_taxons, :pretty_name, if_not_exists: true

    add_column :pallastrade_taxon_translations, :pretty_name, :string, null: true, if_not_exists: true
    add_index :pallastrade_taxon_translations, :pretty_name, if_not_exists: true
  end
end
