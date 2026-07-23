# This migration comes from pallastrade (originally 20210929093238)
class CreatePallasTradeDigitals < ActiveRecord::Migration[5.2]
  def change
    create_table :pallastrade_digitals, if_not_exists: true do |t|
      t.belongs_to :variant

      t.timestamps
    end
  end
end
