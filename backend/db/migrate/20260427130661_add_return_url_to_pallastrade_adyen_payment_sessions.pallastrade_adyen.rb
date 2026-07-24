# This migration comes from pallastrade_adyen (originally 20250813152608)
class AddReturnUrlToPallasTradeAdyenPaymentSessions < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_adyen_payment_sessions, :return_url, :string

    legacy_sessions = Class.new(ActiveRecord::Base) { self.table_name = 'pallastrade_adyen_payment_sessions' }
    legacy_sessions.reset_column_information
    PallasTrade::Store.find_each do |store|
      return_url = store.storefront_url
      legacy_sessions.where(payment_method_id: store.payment_methods.adyen.select(:id), return_url: nil).update_all(return_url: return_url)
    end

    add_index :pallastrade_adyen_payment_sessions, :return_url
  end
end