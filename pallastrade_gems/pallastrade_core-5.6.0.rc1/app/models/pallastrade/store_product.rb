module PallasTrade
  # Thin AR wrapper over the legacy +PALLASTRADE_products_stores+ join table.
  # Pre-5.5 core used this table to attach products to stores; 5.5+ moved
  # that responsibility onto +PallasTrade::Product#store_id+ + +ProductPublication+.
  #
  # The model exists only to power the 5.4 → 5.5 backfill rake task
  # (+spree:upgrade:populate_publications+). Host apps upgrading from 5.4
  # still have the table; after the backfill runs, +PALLASTRADE_multi_store+ (for
  # multi-store catalogs) keeps the table around, and single-store
  # installations may drop it.
  class StoreProduct < PallasTrade.base_class
    self.table_name = 'pallastrade_pallastrade_products_stores'

    belongs_to :product, class_name: 'PallasTrade::Product'
    belongs_to :store, class_name: 'PallasTrade::Store'
  end
end
