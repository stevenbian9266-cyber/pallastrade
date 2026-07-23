class AddMetadataToPallasTradeVariants < ActiveRecord::Migration[5.2]
  def change
    change_table :pallastrade_variants do |t|
      if t.respond_to? :jsonb
        add_column :pallastrade_variants, :public_metadata, :jsonb
        add_column :pallastrade_variants, :private_metadata, :jsonb
      else
        add_column :pallastrade_variants, :public_metadata, :json
        add_column :pallastrade_variants, :private_metadata, :json
      end
    end
  end
end
