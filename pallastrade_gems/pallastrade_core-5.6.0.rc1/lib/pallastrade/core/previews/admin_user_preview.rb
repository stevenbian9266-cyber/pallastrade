require_relative 'preview_data'

# Preview Spree admin user auth emails at /rails/mailers/pallastrade/admin_user
class PallasTrade::AdminUserPreview < ActionMailer::Preview
  include PallasTrade::PreviewData::LocaleParam

  def password_reset_email
    PallasTrade::AdminUserMailer.password_reset_email(
      PallasTrade::PreviewData.admin_user,
      'preview-token',
      PallasTrade::PreviewData.store(locale)
    )
  end

  def confirmation_email
    PallasTrade::AdminUserMailer.confirmation_email(
      PallasTrade::PreviewData.admin_user,
      'preview-token',
      PallasTrade::PreviewData.store(locale)
    )
  end
end
