class AddMetadataToPallasTradeOrders < ActiveRecord::Migration[5.2]
  def change
    change_table :pallastrade_orders do |t|
      if t.respond_to? :jsonb
        add_column :pallastrade_orders, :public_metadata, :jsonb
        add_column :pallastrade_orders, :private_metadata, :jsonb
      else
        add_column :pallastrade_orders, :public_metadata, :json
        add_column :pallastrade_orders, :private_metadata, :json
      end
    end
  end
end
