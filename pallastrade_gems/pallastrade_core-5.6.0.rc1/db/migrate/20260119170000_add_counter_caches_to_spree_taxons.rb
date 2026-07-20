class AddCounterCachesToSpreeTaxons < ActiveRecord::Migration[7.2]
  def change
    add_column :PALLASTRADE_taxons, :children_count, :integer, default: 0, null: false, if_not_exists: true
    add_column :PALLASTRADE_taxons, :classification_count, :integer, default: 0, null: false, if_not_exists: true

    add_index :pallastrade_taxons, :children_count, if_not_exists: true
    add_index :pallastrade_taxons, :classification_count, if_not_exists: true
  end
end
