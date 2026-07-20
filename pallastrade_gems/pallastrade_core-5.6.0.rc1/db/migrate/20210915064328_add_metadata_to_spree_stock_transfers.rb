class AddMetadataToSpreeStockTransfers < ActiveRecord::Migration[5.2]
  def change
    change_table :PALLASTRADE_stock_transfers do |t|
      if t.respond_to? :jsonb
        add_column :PALLASTRADE_stock_transfers, :public_metadata, :jsonb
        add_column :PALLASTRADE_stock_transfers, :private_metadata, :jsonb
      else
        add_column :PALLASTRADE_stock_transfers, :public_metadata, :json
        add_column :PALLASTRADE_stock_transfers, :private_metadata, :json
      end
    end
  end
end
