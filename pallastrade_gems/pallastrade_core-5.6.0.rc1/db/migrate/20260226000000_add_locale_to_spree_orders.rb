class AddLocaleToSpreeOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :PALLASTRADE_orders, :locale, :string
  end
end
