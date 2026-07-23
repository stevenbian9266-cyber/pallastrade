# This migration comes from pallastrade (originally 20260601000001)
class CreatePallasTradeProductPublications < ActiveRecord::Migration[7.2]
  def change
    create_table :pallastrade_product_publications do |t|
      t.references :product, null: false
      t.references :channel, null: false
      t.datetime :published_at
      t.datetime :unpublished_at
      t.timestamps
    end

    add_index :pallastrade_product_publications, %i[product_id channel_id], unique: true,
              name: 'index_pallastrade_product_publications_on_product_and_channel'
  end
end
