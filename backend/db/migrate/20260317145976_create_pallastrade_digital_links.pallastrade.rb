# This migration comes from pallastrade (originally 20210929091444)
class CreatePallasTradeDigitalLinks < ActiveRecord::Migration[5.2]
  def change
    create_table :pallastrade_digital_links, if_not_exists: true do |t|
      t.belongs_to :digital
      t.belongs_to :line_item
      t.string :secret
      t.integer :access_counter

      t.timestamps
    end
    add_index :pallastrade_digital_links, :secret, unique: true unless index_exists?(:pallastrade_digital_links, :secret)
  end
end
