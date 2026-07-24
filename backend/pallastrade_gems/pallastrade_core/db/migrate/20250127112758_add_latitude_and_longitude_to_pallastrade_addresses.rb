class AddLatitudeAndLongitudeToPallasTradeAddresses < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_addresses, :latitude, :decimal, if_not_exists: true
    add_column :pallastrade_addresses, :longitude, :decimal, if_not_exists: true
  end
end
