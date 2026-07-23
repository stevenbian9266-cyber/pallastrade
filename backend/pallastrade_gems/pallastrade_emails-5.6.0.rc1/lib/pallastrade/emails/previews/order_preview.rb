require 'pallastrade/core/previews/preview_data'

# Preview PallasTrade order emails at /rails/mailers/pallastrade/order
class PallasTrade::OrderPreview < ActionMailer::Preview
  include PallasTrade::PreviewData::LocaleParam

  def confirm_email
    PallasTrade::OrderMailer.confirm_email(order)
  end

  def cancel_email
    PallasTrade::OrderMailer.cancel_email(order)
  end

  def store_owner_notification_email
    PallasTrade::OrderMailer.store_owner_notification_email(order)
  end

  private

  # The most recent complete order, with its locale overridden in memory when the
  # preview toolbar requests one (the change is never saved).
  def order
    order = PallasTrade::Order.complete.last
    order.locale = locale if order && locale.present?
    order
  end
end
