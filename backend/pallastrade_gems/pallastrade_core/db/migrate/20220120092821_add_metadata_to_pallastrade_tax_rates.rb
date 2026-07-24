class AddMetadataToPallasTradeTaxRates < ActiveRecord::Migration[5.2]
  def change
    change_table :pallastrade_tax_rates do |t|
      if t.respond_to? :jsonb
        add_column :pallastrade_tax_rates, :public_metadata, :jsonb
        add_column :pallastrade_tax_rates, :private_metadata, :jsonb
      else
        add_column :pallastrade_tax_rates, :public_metadata, :json
        add_column :pallastrade_tax_rates, :private_metadata, :json
      end
    end
  end
end
