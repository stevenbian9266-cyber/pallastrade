require 'pallastrade/core/previews/preview_data'

# Preview PallasTrade customer account emails at /rails/mailers/pallastrade/customer
class PallasTrade::CustomerPreview < ActionMailer::Preview
  include PallasTrade::PreviewData::LocaleParam

  def password_reset_email
    PallasTrade::CustomerMailer.password_reset_email(
      PallasTrade::PreviewData.customer,
      'preview-token',
      PallasTrade::PreviewData.store(locale)
    )
  end
end
