# This migration comes from pallastrade (originally 20251110120003)
class AddPriceListIdToPallasTradeLineItems < ActiveRecord::Migration[7.0]
  def change
    add_reference :pallastrade_line_items, :price_list, null: true
  end
end
