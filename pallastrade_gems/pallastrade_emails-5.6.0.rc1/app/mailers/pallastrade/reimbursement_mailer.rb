module PallasTrade
  class ReimbursementMailer < BaseMailer
    helper PallasTrade::MailHelper

    def reimbursement_email(reimbursement, resend = false)
      @reimbursement = reimbursement.respond_to?(:id) ? reimbursement : PallasTrade::Reimbursement.find(reimbursement)
      @order = @reimbursement.order
      current_store = @reimbursement.store || PallasTrade::Store.default
      with_store_locale(current_store, @order.locale) do
        subject = order_email_subject(current_store, PallasTrade.t('reimbursement_mailer.reimbursement_email.subject'), @order.number, resend: resend)
        mail(to: @order.email, subject: subject, store_url: current_store.storefront_url)
      end
    end
  end
end
