class AddTypeToPallasTradePaymentSetupSessions < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_payment_setup_sessions, :type, :string
    add_index :pallastrade_payment_setup_sessions, :type
  end
end
