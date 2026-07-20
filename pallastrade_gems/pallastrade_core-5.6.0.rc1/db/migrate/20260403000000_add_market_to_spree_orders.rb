class AddMarketToSpreeOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :PALLASTRADE_orders, :market, foreign_key: false, index: true
  end
end
