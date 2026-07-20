class AddMetadataToSpreeStores < ActiveRecord::Migration[6.1]
  def change
    change_table :PALLASTRADE_stores do |t|
      if t.respond_to? :jsonb
        add_column :PALLASTRADE_stores, :public_metadata, :jsonb
        add_column :PALLASTRADE_stores, :private_metadata, :jsonb
      else
        add_column :PALLASTRADE_stores, :public_metadata, :json
        add_column :PALLASTRADE_stores, :private_metadata, :json
      end
    end
  end
end
