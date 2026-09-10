# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3a-redemption-ledger (FR-001)
#
# Promotion redemption ledger: one row per (promotion, order) keeping the
# occupancy/commit history (reserved → committed → released). Additive table:
# no existing column/data is touched; historical rows are backfilled by
# `rake pallastrade:promotions:backfill_redemptions`.
class CreatePallasTradePromotionRedemptions < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_promotion_redemptions do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.references :promotion, null: false, foreign_key: { to_table: :pallastrade_promotions }
      t.references :order, null: false, foreign_key: { to_table: :pallastrade_orders }
      t.references :user, foreign_key: { to_table: :pallastrade_users }
      t.references :coupon_code, foreign_key: { to_table: :pallastrade_coupon_codes }

      t.string :state, null: false, default: 'reserved'
      t.decimal :amount, precision: 12, scale: 2
      t.string :currency
      t.datetime :reserved_at
      t.datetime :reserved_until
      t.datetime :committed_at
      t.datetime :released_at
      t.string :release_reason

      t.timestamps
    end

    add_index :pallastrade_promotion_redemptions, %i[promotion_id order_id], unique: true,
                                                                             name: 'index_pt_promo_redemptions_on_promotion_and_order'
    add_index :pallastrade_promotion_redemptions, :coupon_code_id, unique: true,
                                                                   where: "state <> 'released'",
                                                                   name: 'index_pt_promo_redemptions_on_active_coupon_code'
    add_index :pallastrade_promotion_redemptions, %i[store_id state],
              name: 'index_pt_promo_redemptions_on_store_and_state'
    add_index :pallastrade_promotion_redemptions, %i[promotion_id state],
              name: 'index_pt_promo_redemptions_on_promotion_and_state'
  end
end
