# frozen_string_literal: true

module PallasTrade
  module Admin
    # Email configuration page (Email → Settings): SMTP delivery channel,
    # from/reply addresses, logo, transactional toggle and reply switch.
    # Reuses the store's email preferences so existing fields keep working.
    class EmailsController < PallasTrade::Admin::BaseController
      # 面包屑由导航自动推导（P3）：Emails → Email Settings
      before_action :load_store, only: [:show, :update]

      def show; end

      # POST /admin/emails/test_send — send a test email using the store's
      # current SMTP settings (or the platform default when no per-store SMTP
      # is configured).
      def test_send
        to = params[:to_email].presence || current_admin_user.email
        subject = PallasTrade.t('admin.emails.test_subject', store_name: current_store.name)
        body = PallasTrade.t('admin.emails.test_body')

        if PallasTrade::TestMailer.test_email(
          to: to,
          subject: subject,
          body_html: "<p>#{body}</p>",
          body_text: body,
          store: current_store
        ).deliver_now
          flash[:success] = PallasTrade.t('admin.emails.test_sent', email: to)
        else
          flash[:error] = PallasTrade.t('admin.emails.test_send_failed')
        end
      rescue StandardError => e
        Rails.logger.warn("[emails] test send failed: #{e.class}: #{e.message}")
        flash[:error] = "#{PallasTrade.t('admin.emails.test_send_failed')} #{e.message}"
      ensure
        redirect_to PallasTrade.admin_emails_path
      end

      def update
        @store.assign_attributes(permitted_store_params)

        if @store.save
          remove_assets(%w[mailer_logo], object: @store)
          respond_to do |format|
            format.turbo_stream { flash.now[:success] = PallasTrade.t('admin.emails.saved') }
            format.html { flash[:success] = PallasTrade.t('admin.emails.saved') }
          end
        else
          flash[:error] = "#{PallasTrade.t('store_errors.unable_to_update')}: #{@store.errors.full_messages.join(', ')}"
        end

        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to PallasTrade.admin_emails_path }
        end
      end

      private

      def load_store
        @store = current_store
      end

      def permitted_store_params
        params.require(:store).permit(
          :mail_from_address,
          :customer_support_email,
          :new_order_notifications_email,
          :mailer_logo,
          *current_store.preferences.keys.map { |key| "preferred_#{key}" }
        )
      end
    end
  end
end
