# frozen_string_literal: true

module PallasTrade
  class BackInStockMailer < BaseMailer
    # Notify a customer that the product they subscribed to is back in stock.
    # Delivered via the store's configured SMTP (works with Resend — set
    # SMTP_HOST=smtp.resend.com + SMTP_USERNAME=resend + SMTP_PASSWORD=<api key>).
    def back_in_stock(subscription)
      @subscription = subscription
      @product = subscription.product
      store = @product.store

      with_store_locale(store) do
        mail(
          to: subscription.email,
          subject: PallasTrade.t('back_in_stock_mailer.back_in_stock.subject', product_name: @product.name),
        )
      end
    end
  end
end
