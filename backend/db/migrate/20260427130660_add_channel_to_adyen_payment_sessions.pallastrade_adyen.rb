# This migration comes from pallastrade_adyen (originally 20250811140113)
class AddChannelToAdyenPaymentSessions < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_adyen_payment_sessions, :channel, :string

    PallasTradeAdyen::PaymentSession.reset_column_information
    PallasTradeAdyen::PaymentSession.where(channel: nil).update_all(channel: 'Web')

    add_index :pallastrade_adyen_payment_sessions, :channel
  end
end
