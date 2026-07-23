# This migration comes from pallastrade (originally 20260508204040)
class CreatePallasTradeChannels < ActiveRecord::Migration[7.2]
  def change
    create_table :pallastrade_channels do |t|
      t.references :store, null: false
      t.string :name, null: false
      t.string :code, null: false
      t.boolean :active, null: false
      t.text :preferences
      t.timestamps
    end

    add_index :pallastrade_channels, %i[store_id code], unique: true

    # Default-channel backfill for existing stores lives in
    # +rake pallastrade:channels:create_defaults+ (data transformations don't belong
    # in migrations per PallasTrade's guidelines).
  end
end
