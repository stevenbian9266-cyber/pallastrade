class AddMetadataToSpreeMultipleTables < ActiveRecord::Migration[5.2]
  def change
    %i[
      PALLASTRADE_assets
      PALLASTRADE_option_types
      PALLASTRADE_option_values
      PALLASTRADE_promotions
      PALLASTRADE_payment_methods
      PALLASTRADE_shipping_methods
      PALLASTRADE_prototypes
      PALLASTRADE_refunds
      PALLASTRADE_customer_returns
      PALLASTRADE_users
      PALLASTRADE_addresses
      PALLASTRADE_credit_cards
      PALLASTRADE_store_credits
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
