class AddMetadataToPallasTradePayments < ActiveRecord::Migration[5.2]
  def change
    change_table :pallastrade_payments do |t|
      if t.respond_to? :jsonb
        add_column :pallastrade_payments, :public_metadata, :jsonb
        add_column :pallastrade_payments, :private_metadata, :jsonb
      else
        add_column :pallastrade_payments, :public_metadata, :json
        add_column :pallastrade_payments, :private_metadata, :json
      end
    end
  end
end
