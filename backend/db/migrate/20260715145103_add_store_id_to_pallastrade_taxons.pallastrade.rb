# This migration comes from pallastrade (originally 20260626000001)
class AddStoreIdToPallasTradeTaxons < ActiveRecord::Migration[7.2]
  # NOTE: After running this migration, existing taxons have +store_id IS NULL+
  # and keep resolving their store through their taxonomy (Taxon.for_store falls
  # back to the taxonomy join). Run the backfill to populate +store_id+ directly,
  # which is what taxonomy-less categories (PallasTrade::Category) rely on:
  #
  #   bundle exec rake pallastrade:taxons:backfill_store_id
  def change
    add_reference :pallastrade_taxons, :store, null: true, if_not_exists: true
  end
end
