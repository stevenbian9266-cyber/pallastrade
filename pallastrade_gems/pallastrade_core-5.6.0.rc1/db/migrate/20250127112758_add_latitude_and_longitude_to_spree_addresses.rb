class AddLatitudeAndLongitudeToSpreeAddresses < ActiveRecord::Migration[6.1]
  def change
    add_column :PALLASTRADE_addresses, :latitude, :decimal, if_not_exists: true
    add_column :PALLASTRADE_addresses, :longitude, :decimal, if_not_exists: true
  end
end
