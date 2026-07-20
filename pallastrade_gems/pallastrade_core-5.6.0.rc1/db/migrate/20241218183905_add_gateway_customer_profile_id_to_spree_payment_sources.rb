class AddGatewayCustomerProfileIdToSpreePaymentSources < ActiveRecord::Migration[6.1]
  def change
    add_column :PALLASTRADE_payment_sources, :gateway_customer_profile_id, :string
  end
end
