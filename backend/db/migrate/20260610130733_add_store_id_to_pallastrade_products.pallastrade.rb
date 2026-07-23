# This migration comes from pallastrade (originally 20260601000002)
class AddStoreIdToPallasTradeProducts < ActiveRecord::Migration[7.2]
  # NOTE: After running this migration, existing products will have
  # +store_id IS NULL+ and be invisible to +Product.for_store+. Operators
  # upgrading from 5.4 MUST run the backfill task immediately afterwards:
  #
  #   bundle exec rake pallastrade:upgrade:populate_publications
  #
  # The backfill is also chained from +pallastrade:channels:upgrade+ so the full
  # 5.4 → 5.5 channel/publication upgrade is one command.
  def change
    add_reference :pallastrade_products, :store, null: true
    add_column :pallastrade_products, :units_sold_count, :integer, default: 0, null: false
    add_column :pallastrade_products, :revenue, :decimal, precision: 16, scale: 4, default: 0, null: false
    add_index :pallastrade_products, %i[store_id units_sold_count]
  end
end
