class AddMetadataToSpreePayments < ActiveRecord::Migration[5.2]
  def change
    change_table :PALLASTRADE_payments do |t|
      if t.respond_to? :jsonb
        add_column :PALLASTRADE_payments, :public_metadata, :jsonb
        add_column :PALLASTRADE_payments, :private_metadata, :jsonb
      else
        add_column :PALLASTRADE_payments, :public_metadata, :json
        add_column :PALLASTRADE_payments, :private_metadata, :json
      end
    end
  end
end
