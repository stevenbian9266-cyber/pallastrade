# This migration comes from pallastrade (originally 20250114193857)
class AddMetadataToPallasTradeStores < ActiveRecord::Migration[6.1]
  def change
    change_table :pallastrade_stores do |t|
      if t.respond_to? :jsonb
        add_column :pallastrade_stores, :public_metadata, :jsonb
        add_column :pallastrade_stores, :private_metadata, :jsonb
      else
        add_column :pallastrade_stores, :public_metadata, :json
        add_column :pallastrade_stores, :private_metadata, :json
      end
    end
  end
end
