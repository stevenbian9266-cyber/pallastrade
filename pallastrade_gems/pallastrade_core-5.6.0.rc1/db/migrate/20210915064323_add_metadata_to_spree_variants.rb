class AddMetadataToSpreeVariants < ActiveRecord::Migration[5.2]
  def change
    change_table :PALLASTRADE_variants do |t|
      if t.respond_to? :jsonb
        add_column :PALLASTRADE_variants, :public_metadata, :jsonb
        add_column :PALLASTRADE_variants, :private_metadata, :jsonb
      else
        add_column :PALLASTRADE_variants, :public_metadata, :json
        add_column :PALLASTRADE_variants, :private_metadata, :json
      end
    end
  end
end
