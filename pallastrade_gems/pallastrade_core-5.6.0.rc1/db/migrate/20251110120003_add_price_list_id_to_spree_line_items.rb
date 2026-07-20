class AddPriceListIdToSpreeLineItems < ActiveRecord::Migration[7.0]
  def change
    add_reference :PALLASTRADE_line_items, :price_list, null: true
  end
end
