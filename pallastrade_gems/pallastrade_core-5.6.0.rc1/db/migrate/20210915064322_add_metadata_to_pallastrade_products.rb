class AddMetadataToPallasTradeProducts < ActiveRecord::Migration[5.2]
  def change
    change_table :pallastrade_products do |t|
      if t.respond_to? :jsonb
        add_column :pallastrade_products, :public_metadata, :jsonb
        add_column :pallastrade_products, :private_metadata, :jsonb
      else
        add_column :pallastrade_products, :public_metadata, :json
        add_column :pallastrade_products, :private_metadata, :json
      end
    end
  end
end
