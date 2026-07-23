module PallasTrade
  class ShipmentMailer < BaseMailer
    helper PallasTrade::MailHelper
    helper PallasTrade::ShipmentHelper

    def shipped_email(shipment, resend = false)
      @shipment = shipment.respond_to?(:id) ? shipment : PallasTrade::Shipment.find(shipment)
      @order = @shipment.order
      current_store = @shipment.store
      with_store_locale(current_store, @order.locale) do
        subject = order_email_subject(current_store, PallasTrade.t('shipment_mailer.shipped_email.subject'), @order.number, resend: resend)
        mail(to: @order.email, subject: subject, store_url: current_store.storefront_url)
      end
    end
  end
end
