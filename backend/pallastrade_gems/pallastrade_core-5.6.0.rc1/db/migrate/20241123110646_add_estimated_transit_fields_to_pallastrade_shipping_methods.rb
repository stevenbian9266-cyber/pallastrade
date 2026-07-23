class AddEstimatedTransitFieldsToPallasTradeShippingMethods < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_shipping_methods, :estimated_transit_business_days_min, :integer
    add_column :pallastrade_shipping_methods, :estimated_transit_business_days_max, :integer
  end
end
