# frozen_string_literal: true

# Batch C-2 (PRD-20260915-catalog-batch-c2-sku-back-in-stock):
# back-in-stock subscriptions become SKU-aware.
#
# `variant_id` stays nullable so the historical product-level subscriptions keep
# working: those are notified by `product.back_in_stock` (whole product back),
# while SKU subscribers are notified by `variant.back_in_stock` (their own SKU).
class AddVariantToBackInStockSubscriptions < ActiveRecord::Migration[8.1]
  def up
    add_column :pallastrade_back_in_stock_subscriptions, :variant_id, :bigint
    add_index :pallastrade_back_in_stock_subscriptions, :variant_id,
              name: 'index_bis_subscriptions_on_variant_id'
    add_foreign_key :pallastrade_back_in_stock_subscriptions, :pallastrade_variants, column: :variant_id

    # One subscription per (product, SKU, email) …
    remove_index :pallastrade_back_in_stock_subscriptions, name: 'index_bis_subscriptions_on_product_and_email'
    add_index :pallastrade_back_in_stock_subscriptions, %i[product_id variant_id email],
              unique: true, where: 'variant_id IS NOT NULL',
              name: 'index_bis_subscriptions_on_product_variant_and_email'
    # … while the legacy product-level rule (one per product + email) is kept.
    add_index :pallastrade_back_in_stock_subscriptions, %i[product_id email],
              unique: true, where: 'variant_id IS NULL',
              name: 'index_bis_subscriptions_on_product_and_email'
  end

  def down
    remove_index :pallastrade_back_in_stock_subscriptions, name: 'index_bis_subscriptions_on_product_variant_and_email'
    remove_index :pallastrade_back_in_stock_subscriptions, name: 'index_bis_subscriptions_on_product_and_email'
    add_index :pallastrade_back_in_stock_subscriptions, %i[product_id email],
              unique: true, name: 'index_bis_subscriptions_on_product_and_email'

    remove_foreign_key :pallastrade_back_in_stock_subscriptions, column: :variant_id
    remove_index :pallastrade_back_in_stock_subscriptions, name: 'index_bis_subscriptions_on_variant_id'
    remove_column :pallastrade_back_in_stock_subscriptions, :variant_id
  end
end
