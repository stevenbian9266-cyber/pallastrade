class AddPreferredStockLocationToSpreeOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :PALLASTRADE_orders, :preferred_stock_location
  end
end
