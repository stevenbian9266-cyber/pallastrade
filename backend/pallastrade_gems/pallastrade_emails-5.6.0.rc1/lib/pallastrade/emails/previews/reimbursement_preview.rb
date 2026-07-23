require 'pallastrade/core/previews/preview_data'

# Preview PallasTrade reimbursement emails at /rails/mailers/pallastrade/reimbursement
class PallasTrade::ReimbursementPreview < ActionMailer::Preview
  include PallasTrade::PreviewData::LocaleParam

  def reimbursement_email
    reimbursement = PallasTrade::Reimbursement.last
    reimbursement.order.locale = locale if reimbursement && locale.present?
    PallasTrade::ReimbursementMailer.reimbursement_email(reimbursement)
  end
end
