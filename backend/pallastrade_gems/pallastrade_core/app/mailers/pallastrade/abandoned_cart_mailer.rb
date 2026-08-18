# frozen_string_literal: true

module PallasTrade
  # Abandoned-cart recovery email (P0-3, 2026-08-18). Delivered by
  # `PallasTrade::AbandonedCarts::SendNotificationsJob` via the store's SMTP.
  class AbandonedCartMailer < BaseMailer
    def recovery_email(notification)
      @notification = notification
      @cart = notification.cart
      @recovery_url = recovery_url
      store = @cart.store

      with_store_locale(store, @cart.locale) do
        mail(
          to: notification.email,
          subject: PallasTrade.t('abandoned_cart_mailer.recovery_email.subject', store_name: store.name),
        )
      end
    end

    # Placeholder values available to admin-edited DB templates.
    def email_template_context
      {
        store_name: @cart&.store&.name,
        cart_url: @recovery_url,
        item_count: @cart&.items&.size
      }.compact
    end

    # Exposed to the mailer view as the recovery link.
    helper_method :recovery_url

    # {storefront_url}/{country}/{locale}/checkout/{cart_id}?token={order.token}
    def recovery_url
      return unless @cart

      country = @cart.market&.countries&.first&.iso.to_s.downcase.presence || 'us'
      locale = @cart.locale.to_s.presence || 'en'
      base = "https://#{@cart.store.url}/#{country}/#{locale}/checkout/#{@cart.id}"
      append_token(base, @cart.token)
    end
  end
end
