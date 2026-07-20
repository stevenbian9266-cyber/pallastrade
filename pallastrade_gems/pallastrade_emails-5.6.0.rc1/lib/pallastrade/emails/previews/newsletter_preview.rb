require 'pallastrade/core/previews/preview_data'

# Preview Spree newsletter emails at /rails/mailers/pallastrade/newsletter
class PallasTrade::NewsletterPreview < ActionMailer::Preview
  include PallasTrade::PreviewData::LocaleParam

  def email_confirmation
    PallasTrade::NewsletterMailer.email_confirmation(subscriber)
  end

  private

  def subscriber
    return example_subscriber if locale.present?

    PallasTrade::NewsletterSubscriber.unverified.last || example_subscriber
  end

  # Build an in-memory subscriber so the preview works on a database with no
  # newsletter subscribers. When the preview toolbar requests a locale, its
  # store carries that locale. Never saved, so no records are created.
  def example_subscriber
    subscriber = PallasTrade::NewsletterSubscriber.new(
      email: 'guest@example.com',
      store: PallasTrade::PreviewData.store(locale)
    )
    subscriber.verification_token ||= 'preview-token'
    subscriber
  end
end
