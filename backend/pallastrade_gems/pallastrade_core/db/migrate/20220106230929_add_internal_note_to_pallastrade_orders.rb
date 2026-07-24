class AddInternalNoteToPallasTradeOrders < ActiveRecord::Migration[5.2]
  def change
    add_column :pallastrade_orders, :internal_note, :text
  end
end
