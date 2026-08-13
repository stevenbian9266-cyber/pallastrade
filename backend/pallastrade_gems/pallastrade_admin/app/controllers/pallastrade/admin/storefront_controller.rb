# frozen_string_literal: true

module PallasTrade
  module Admin
    class StorefrontController < BaseController
      include PallasTrade::Admin::SettingsConcern

      # GET /admin/storefront
      def show
        @breadcrumb_icon = 'building-store'
        add_breadcrumb PallasTrade.t('admin.storefront_setup.title'), PallasTrade.admin_storefront_path

        @publishable_key = find_or_create_publishable_key
        @deployment_origin = normalize_origin(params[:'deployment-url'])
        @deployment_origin_allowed = @deployment_origin.present? && current_store.allowed_origin?(@deployment_origin)
        @storefront_origins = current_store.allowed_origins.order(:created_at).reject(&:loopback?)
      end

      # PATCH /admin/storefront
      #
      # Saves the storefront URL preference (used as the base for links in
      # customer emails and as the setup-task completion signal) and adds it
      # as an allowed origin so browser-based storefronts can call the Store API.
      def update
        origin = normalize_origin(params[:storefront_url])

        if origin.nil?
          flash[:error] = PallasTrade.t('admin.storefront_setup.invalid_origin')
        elsif current_store.update(preferred_storefront_url: origin)
          current_store.allowed_origins.find_or_create_by(origin: origin)
          flash[:success] = PallasTrade.t('admin.storefront_setup.storefront_url_saved', url: origin)
        else
          flash[:error] = current_store.errors.full_messages.to_sentence
        end

        redirect_to PallasTrade.admin_storefront_path, status: :see_other
      end

      # POST /admin/storefront/allow_origin
      def allow_origin
        origin = normalize_origin(params[:origin])

        if origin.nil?
          flash[:error] = PallasTrade.t('admin.storefront_setup.invalid_origin')
        else
          allowed_origin = current_store.allowed_origins.find_or_initialize_by(origin: origin)

          if allowed_origin.persisted? || allowed_origin.save
            current_store.update(preferred_storefront_url: origin) if current_store.preferred_storefront_url.blank?
            flash[:success] = PallasTrade.t('admin.storefront_setup.origin_allowed', origin: origin)
          else
            flash[:error] = allowed_origin.errors.full_messages.to_sentence
          end
        end

        redirect_to PallasTrade.admin_storefront_path, status: :see_other
      end

      private

      # Every action here is store configuration (publishable keys, allowed
      # origins, store preferences), so gate the whole page behind store
      # management — granted by e.g. PallasTrade::PermissionSets::ConfigurationManagement.
      def authorize_admin
        authorize! :admin, PallasTrade::Store
        authorize! :update, current_store
      end

      # The storefront needs a publishable key; reuse the oldest active one
      # (usually the seeded "Default") and mint one for stores that have none.
      def find_or_create_publishable_key
        current_store.api_keys.active.publishable.order(:created_at).first ||
          current_store.api_keys.create!(
            name: 'Storefront',
            key_type: 'publishable',
            created_by: try_pallastrade_current_user
          )
      end

      # Normalizes user or deployment-callback input to a canonical origin string,
      # or nil when it's not a valid http(s) URL — pre-normalized here (rather
      # than leaning on the Store validation) so invalid input gets the
      # dedicated invalid_origin flash.
      def normalize_origin(raw)
        PallasTrade::AllowedOrigin.normalize_origin(raw)
      end

    end
  end
end
