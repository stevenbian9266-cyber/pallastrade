class AddCustomCodeFieldsToPallasTradeStore < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_stores, :storefront_custom_code_head, :text
    add_column :pallastrade_stores, :storefront_custom_code_body_start, :text
    add_column :pallastrade_stores, :storefront_custom_code_body_end, :text
  end
end
