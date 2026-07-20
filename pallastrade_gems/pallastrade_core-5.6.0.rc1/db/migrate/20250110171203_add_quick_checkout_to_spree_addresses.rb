class AddQuickCheckoutToSpreeAddresses < ActiveRecord::Migration[6.1]
  def change
    add_column :PALLASTRADE_addresses, :quick_checkout, :boolean, default: false, if_not_exists: true
    add_index :pallastrade_addresses, :quick_checkout, if_not_exists: true
  end
end
