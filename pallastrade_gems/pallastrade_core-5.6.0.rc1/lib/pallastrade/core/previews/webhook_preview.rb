require_relative 'preview_data'

# Preview PallasTrade webhook notification emails at /rails/mailers/pallastrade/webhook
class PallasTrade::WebhookPreview < ActionMailer::Preview
  include PallasTrade::PreviewData::LocaleParam

  def endpoint_disabled
    PallasTrade::WebhookMailer.endpoint_disabled(webhook_endpoint)
  end

  private

  # Reuse the most recent endpoint, or build an in-memory disabled example so the
  # preview works on a database with no webhook endpoints. When the preview
  # toolbar requests a locale, always use the example so its store carries that
  # locale. Never saved, so the admin webhook list stays clean.
  def webhook_endpoint
    return example_endpoint if locale.present?

    PallasTrade::WebhookEndpoint.last || example_endpoint
  end

  def example_endpoint
    PallasTrade::WebhookEndpoint.new(
      store: PallasTrade::PreviewData.store(locale),
      name: 'Example endpoint',
      url: 'https://example.com/webhooks/spree',
      active: false,
      disabled_reason: 'Too many failed delivery attempts',
      disabled_at: Time.current,
      subscriptions: ['order.completed']
    )
  end
end
