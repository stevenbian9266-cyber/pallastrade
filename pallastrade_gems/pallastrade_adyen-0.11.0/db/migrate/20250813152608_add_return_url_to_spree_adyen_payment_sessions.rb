class AddReturnUrlToPallasTradeAdyenPaymentSessions < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_adyen_payment_sessions, :return_url, :string

    PallasTradeAdyen::PaymentSession.reset_column_information
    PallasTrade::Store.find_each do |store|
      redirect_to = PallasTrade::Core::Engine.routes.url_helpers.redirect_adyen_payment_session_url(host: store.url_or_custom_domain)
      store.payment_methods.adyen.find_each do |gateway|
        store.adyen_gateway.payment_sessions.with_deleted.where(return_url: nil).update_all(return_url: redirect_to)
      end
    end

    add_index :pallastrade_adyen_payment_sessions, :return_url
  end
end