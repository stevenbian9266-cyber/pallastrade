class AddMetadataToSpreeShipments < ActiveRecord::Migration[5.2]
  def change
    change_table :PALLASTRADE_shipments do |t|
      if t.respond_to? :jsonb
        add_column :PALLASTRADE_shipments, :public_metadata, :jsonb
        add_column :PALLASTRADE_shipments, :private_metadata, :jsonb
      else
        add_column :PALLASTRADE_shipments, :public_metadata, :json
        add_column :PALLASTRADE_shipments, :private_metadata, :json
      end
    end
  end
end
