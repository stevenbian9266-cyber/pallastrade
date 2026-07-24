class AddLocaleToPallasTradeOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_orders, :locale, :string
  end
end
