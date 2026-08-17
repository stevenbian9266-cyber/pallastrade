module PallasTrade
  module Admin
    class StoresController < PallasTrade::Admin::BaseController
      include PallasTrade::Admin::SettingsConcern
      include Pagy::Method

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

      # PALLAS-CUSTOM: 多店铺管理（2026-08-17）——店铺列表
      def index
        @search = PallasTrade::Store.ransack(params[:q])
        @pagy, @collection = pagy(@search.result.order(:created_at), limit: params[:per_page] || 25)
      end

      # PALLAS-CUSTOM: 多店铺管理（2026-08-17）——新建店铺
      def new
        @store = PallasTrade::Store.new
      end

      # PALLAS-CUSTOM: 多店铺管理（2026-08-17）——创建店铺：初始化默认策略 → 授予当前用户管理角色 → 自动切换
      def create
        params[:store][:mail_from_address] = default_mail_from_address if params[:store][:mail_from_address].blank?
        @store = PallasTrade::Store.new(permitted_create_params)
        if @store.save
          grant_creator_admin_access(@store)
          session[:admin_store_id] = @store.id
          flash[:success] = PallasTrade.t('admin.stores.created')
          redirect_to PallasTrade.edit_admin_store_path, status: :see_other
        else
          flash[:error] = "#{PallasTrade.t('admin.stores.create_error')}: #{@store.errors.full_messages.join(', ')}"
          render :new, status: :unprocessable_content
        end
      end

      # PALLAS-CUSTOM: 多店铺管理（2026-08-17）——按 url 生成默认发件邮箱（Store 必填）
      def default_mail_from_address
        host = params[:store][:url].to_s.sub(%r{^https?://}, '').split('/').first.presence
        host ? "no-reply@#{host}" : nil
      end

      # PALLAS-CUSTOM: 多店铺管理（2026-08-17）——切换店铺（POST /admin/switch_store）
      # 超管切换到无 RoleUser 的店铺时自动授予 admin 角色（保证该店角色按店解析命中）。
      def switch_store
        store = PallasTrade::Store.find_by(id: params[:store_id])
        if store && admin_accessible_stores.include?(store)
          grant_store_access(store)
          session[:admin_store_id] = store.id
          flash[:success] = PallasTrade.t('admin.stores.switched', name: store.name)
        else
          flash[:error] = PallasTrade.t('admin.stores.cannot_switch')
        end
        redirect_back fallback_location: PallasTrade.admin_path, status: :see_other
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

      # PALLAS-CUSTOM: 多店铺管理（2026-08-17）——新建店铺白名单（参照 store 工厂字段）
      def permitted_create_params
        params.require(:store).permit(
          :code, :name, :url, :mail_from_address, :customer_support_email,
          :new_order_notifications_email, :default_currency, :supported_currencies, :default_locale
        )
      end

      private

      # PALLAS-CUSTOM: 多店铺管理（2026-08-17）——创建后授予当前用户该店铺的 admin 角色
      def grant_creator_admin_access(store)
        grant_store_access(store)
      end

      # PALLAS-CUSTOM: 多店铺管理（2026-08-17）——确保当前用户对该店铺有 admin RoleUser
      def grant_store_access(store)
        user = try_pallastrade_current_user
        return unless user
        return if PallasTrade::RoleUser.where(user: user, resource: store, resource_type: 'PallasTrade::Store').exists?

        role = PallasTrade::Role.default_admin_role
        PallasTrade::RoleUser.create!(user: user, role: role, resource: store, store: store)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        nil
      end

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
