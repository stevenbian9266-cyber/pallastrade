class AddMetadataToSpreeOrders < ActiveRecord::Migration[5.2]
  def change
    change_table :PALLASTRADE_orders do |t|
      if t.respond_to? :jsonb
        add_column :PALLASTRADE_orders, :public_metadata, :jsonb
        add_column :PALLASTRADE_orders, :private_metadata, :jsonb
      else
        add_column :PALLASTRADE_orders, :public_metadata, :json
        add_column :PALLASTRADE_orders, :private_metadata, :json
      end
    end
  end
end
