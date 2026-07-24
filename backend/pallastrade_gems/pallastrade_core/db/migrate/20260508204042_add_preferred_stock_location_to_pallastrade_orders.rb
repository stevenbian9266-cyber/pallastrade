class AddPreferredStockLocationToPallasTradeOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :pallastrade_orders, :preferred_stock_location
  end
end
