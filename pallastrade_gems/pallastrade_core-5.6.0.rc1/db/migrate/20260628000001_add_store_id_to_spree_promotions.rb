class AddStoreIdToSpreePromotions < ActiveRecord::Migration[7.2]
  # NOTE: After running this migration, existing promotions have +store_id IS NULL+
  # and are invisible to +Promotion.for_store+. Run the backfill immediately to
  # copy ownership from the legacy +PALLASTRADE_promotions_stores+ join table:
  #
  #   bundle exec rake spree:upgrade:populate_single_store_associations
  def change
    add_reference :PALLASTRADE_promotions, :store, null: true, if_not_exists: true
  end
end
