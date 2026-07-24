class AddMarketToPallasTradeOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :pallastrade_orders, :market, foreign_key: false, index: true
  end
end
