class AddMetadataToPallasTradeLineItems < ActiveRecord::Migration[5.2]
  def change
    change_table :pallastrade_line_items do |t|
      if t.respond_to? :jsonb
        add_column :pallastrade_line_items, :public_metadata, :jsonb
        add_column :pallastrade_line_items, :private_metadata, :jsonb
      else
        add_column :pallastrade_line_items, :public_metadata, :json
        add_column :pallastrade_line_items, :private_metadata, :json
      end
    end
  end
end
