class AddMetadataToPallasTradeMultipleTables < ActiveRecord::Migration[5.2]
  def change
    %i[
      pallastrade_assets
      pallastrade_option_types
      pallastrade_option_values
      pallastrade_promotions
      pallastrade_payment_methods
      pallastrade_shipping_methods
      pallastrade_prototypes
      pallastrade_refunds
      pallastrade_customer_returns
      pallastrade_users
      pallastrade_addresses
      pallastrade_credit_cards
      pallastrade_store_credits
    ].each do |table_name|
      change_table table_name do |t|
        if t.respond_to? :jsonb
          add_column table_name, :public_metadata, :jsonb
          add_column table_name, :private_metadata, :jsonb
        else
          add_column table_name, :public_metadata, :json
          add_column table_name, :private_metadata, :json
        end
      end
    end
  end
end
