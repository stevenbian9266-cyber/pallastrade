# frozen_string_literal: true

module PallasTrade
  module Admin
    # Email configuration page (Email → Settings): SMTP delivery channel,
    # from/reply addresses, logo, transactional toggle and reply switch.
    # Reuses the store's email preferences so existing fields keep working.
    class EmailsController < PallasTrade::Admin::BaseController
      before_action :load_store, only: [:show, :update]

      def show
        add_breadcrumb PallasTrade.t(:emails), PallasTrade.admin_emails_path
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
