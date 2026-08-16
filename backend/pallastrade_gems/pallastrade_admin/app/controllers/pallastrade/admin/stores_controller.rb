module PallasTrade
  module Admin
    class StoresController < PallasTrade::Admin::BaseController
      include PallasTrade::Admin::SettingsConcern

      # 面包屑按 section 自定义（Checkout / Store Details），保留手写；跳过自动推导（P5）
      self.skip_breadcrumb_derivation = true

      before_action :load_store, only: [:edit, :update]
      before_action :normalize_supported_currencies, only: [:update]
      before_action :normalize_supported_locales, only: [:update]
      before_action :load_all_countries, only: [:edit, :update]

      def edit
        # Email settings moved to the top-level Email menu (Email → Settings).
        # Redirect legacy /admin/store/edit?section=emails so there is a single
        # entry point. See pallastrade_admin_navigation.rb (Email submenu).
        if params[:section] == 'emails'
          return redirect_to PallasTrade.admin_emails_path
        end

        if params[:section] == 'checkout'
          add_breadcrumb PallasTrade.t(:checkout), PallasTrade.edit_admin_store_path(section: params[:section])
        else
          add_breadcrumb PallasTrade.t(:store_details), PallasTrade.edit_admin_store_path(section: params[:section])
        end
      end

      def edit_emails
        redirect_to PallasTrade.admin_emails_path
      end

      def update
        @store.assign_attributes(permitted_store_params)

        if @store.save
          remove_assets(%w[logo mailer_logo], object: @store)
          respond_to do |format|
            format.turbo_stream { flash.now[:success] = flash_message_for(@store, :successfully_updated) }
            format.html { flash[:success] = flash_message_for(@store, :successfully_updated) }
          end
        else
          flash[:error] = "#{PallasTrade.t('store_errors.unable_to_update')}: #{@store.errors.full_messages.join(', ')}"
        end

        if @store.saved_changes? && permitted_store_params[:code].present? && PallasTrade.respond_to?(:admin_custom_domains_url)
          redirect_to PallasTrade.admin_custom_domains_url(host: @store.url), allow_other_host: true
        elsif params[:section] == 'emails'
          # Email settings now live under the top-level Email menu.
          redirect_to PallasTrade.admin_emails_path
        else
          respond_to do |format|
            format.turbo_stream
            format.html { redirect_to PallasTrade.edit_admin_store_path(section: params[:section]) }
          end
        end
      end

      protected

      def permitted_store_params
        params.require(:store).permit(permitted_store_attributes + current_store.preferences.keys.map { |key| "preferred_#{key}" })
      end

      private

      def load_store
        @store = current_store
      end

      def load_all_countries
        @countries = PallasTrade::Country.pluck(:name, :id)
      end

      def normalize_supported_currencies
        if params.dig(:store, :supported_currencies)&.is_a?(Array)
          params[:store][:supported_currencies] = params[:store][:supported_currencies].compact.uniq.reject(&:blank?).join(',')
        end
      end

      def normalize_supported_locales
        if params.dig(:store, :supported_locales)&.is_a?(Array)
          params[:store][:supported_locales] = params[:store][:supported_locales].compact.uniq.reject(&:blank?).join(',')
        end
      end
    end
  end
end
