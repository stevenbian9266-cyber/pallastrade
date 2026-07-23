class AddPriceListIdToPallasTradeLineItems < ActiveRecord::Migration[7.0]
  def change
    add_reference :pallastrade_line_items, :price_list, null: true
  end
end
