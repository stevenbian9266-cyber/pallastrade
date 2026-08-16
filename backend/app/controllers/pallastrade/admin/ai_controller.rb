# frozen_string_literal: true

module PallasTrade
  module Admin
    class AIController < ResourceController
      # AI controller manages multiple resource types (providers, models,
      # capabilities, runs) and loads them via custom before_actions.
      # Standard ResourceController#load_resource is incompatible because
      # model_class cannot represent a single resource type.
      skip_before_action :load_resource

      PROVIDER_TYPES = %w[
        PallasTrade::AI::Provider::DeepSeek
        PallasTrade::AI::Provider::OpenAI
      ].freeze

      # Breadcrumbs — Pattern B (P3 起：模块级 base crumb 由导航自动推导，
      # 即 sidebar 的 ai_tools 项；这里只保留图标 + 子页 crumb)。
      # Sub-page breadcrumbs are appended via before_action.
      add_breadcrumb_icon 'sparkles'

      before_action :add_ai_sub_breadcrumb, only: %i[providers provider models capabilities runs]

      before_action :load_providers, only: %i[index providers]
      before_action :load_models, only: %i[models]
      before_action :load_runs, only: %i[runs]
      before_action :load_capabilities, only: %i[capabilities]

      # GET /admin/ai
      def index
        # Ensure preset providers (DeepSeek/OpenAI) exist so the overview
        # and providers pages show them even before credentials are added.
        PallasTrade::AI::ProvisionProviders.call(store: current_store)

        # Overview page — shows summary of AI configuration
        @setting = PallasTrade::AI::Setting.find_or_initialize_by(store: current_store)
        @provider_count = current_store.ai_providers.where(type: PROVIDER_TYPES).count
        @model_count = PallasTrade::AI::Model.where(store: current_store).count
        @active_model_count = PallasTrade::AI::Model.where(store: current_store, active: true).count
        @cap_count = PallasTrade::AI::CapabilitySetting.where(store: current_store, active: true).count
        @run_count = PallasTrade::AI::Run.where(store: current_store).count
      end

      # GET /admin/ai/providers
      def providers
        # Lazy-provision preset providers so the page shows DeepSeek/OpenAI
        # cards with "Key not configured" status even on first visit.
        PallasTrade::AI::ProvisionProviders.call(store: current_store)
        @providers = current_store.ai_providers.where(type: PROVIDER_TYPES)
      end

      # GET /admin/ai/providers/:id
      def provider
        @provider = find_provider
        @secret = PallasTrade::AI::ProviderSecret.find_by(provider: @provider)
        @models = PallasTrade::AI::Model.where(provider: @provider).order(:name)
      end

      # PATCH /admin/ai/providers/:id
      def update_provider
        @provider = find_provider

        if params[:api_key].present?
          secret = PallasTrade::AI::ProviderSecret.find_or_initialize_by(provider: @provider)
          secret.credentials = params[:api_key]
          secret.save!
        end

        if params.key?(:active)
          @provider.update!(active: ActiveModel::Type::Boolean.new.cast(params[:active]))
        end

        flash[:success] = PallasTrade.t(:updated, default: 'Updated')
        redirect_back fallback_location: PallasTrade.admin_ai_provider_path(@provider)
      rescue ActiveRecord::RecordInvalid => e
        flash[:error] = e.message
        redirect_back fallback_location: PallasTrade.admin_ai_provider_path(@provider)
      end

      # POST /admin/ai/providers/:id/test_connection
      def test_connection
        @provider = find_provider
        entry = PallasTrade::AI.providers[@provider.key.to_sym]

        if entry
          adapter = entry.adapter_class.constantize.new
          result = adapter.test_connection(@provider)
          # Note: verification status persistence is not implemented yet
          # (no verification_status / last_verified_at columns); only report.
          flash[:success] = "Connection #{result[:status]} (latency: #{result[:latency_ms]}ms)"
        else
          flash[:error] = 'Unknown provider type'
        end
        redirect_to PallasTrade.admin_ai_provider_path(@provider)
      rescue StandardError => e
        flash[:error] = e.message
        redirect_to PallasTrade.admin_ai_provider_path(@provider)
      end

      # DELETE /admin/ai/providers/:id/credential
      def clear_credential
        @provider = find_provider
        secret = PallasTrade::AI::ProviderSecret.find_by(provider: @provider)
        secret&.destroy!
        @provider.update!(active: false)
        flash[:success] = 'Credential cleared'
        redirect_to PallasTrade.admin_ai_provider_path(@provider)
      end

      # GET /admin/ai/models
      def models
        provision_models_for_all_providers
        @models = PallasTrade::AI::Model.where(store: current_store).includes(:provider).order(:name)
      end

      # PATCH /admin/ai/models/:id
      def update_model
        @model = PallasTrade::AI::Model.where(store: current_store).find(params[:id])
        # A checkbox that is unchecked does not submit its param, so params[:active]
        # is nil — coerce nil → false (Boolean#cast(nil) returns nil and would
        # violate the not-null constraint on pallastrade_ai_models.active).
        active = ActiveModel::Type::Boolean.new.cast(params[:active]) == true
        @model.update!(active: active)
        respond_to do |format|
          format.turbo_stream do
            flash.now[:success] = 'Model updated'
          end
          format.html do
            flash[:success] = 'Model updated'
            redirect_back fallback_location: PallasTrade.admin_ai_models_path
          end
        end
      rescue ActiveRecord::RecordInvalid => e
        respond_to do |format|
          format.turbo_stream do
            flash.now[:error] = e.message
            # Re-render the row with the unchanged state (update! rolled back)
            render :update_model
          end
          format.html do
            flash[:error] = e.message
            redirect_back fallback_location: PallasTrade.admin_ai_models_path
          end
        end
      end

      # GET /admin/ai/capabilities
      def capabilities
        @capabilities = PallasTrade::AI.capabilities.all.map do |entry|
          setting = PallasTrade::AI::CapabilitySetting.find_by(store: current_store, capability_key: entry.key)
          { entry: entry, setting: setting }
        end
      end

      # PATCH /admin/ai/capabilities/:capability_key
      def update_capability
        setting = PallasTrade::AI::CapabilitySetting.find_or_initialize_by(
          store: current_store,
          capability_key: params[:capability_key]
        )
        setting.update!(
          active: ActiveModel::Type::Boolean.new.cast(params[:active]),
          primary_model_id: params[:primary_model_id].presence,
          fallback_enabled: ActiveModel::Type::Boolean.new.cast(params[:fallback_enabled])
        )
        flash[:success] = 'Capability updated'
        redirect_to PallasTrade.admin_ai_capabilities_path
      rescue ActiveRecord::RecordInvalid => e
        flash[:error] = e.message
        redirect_to PallasTrade.admin_ai_capabilities_path
      end

      # GET /admin/ai/runs
      def runs
        @runs = PallasTrade::AI::Run.where(store: current_store).recent
      end

      # PATCH /admin/ai/settings
      def update_settings
        setting = PallasTrade::AI::Setting.find_or_initialize_by(store: current_store)
        setting.update!(active: ActiveModel::Type::Boolean.new.cast(params[:active]))
        flash[:success] = 'Setting updated'
        redirect_to PallasTrade.admin_ai_path
      rescue ActiveRecord::RecordInvalid => e
        flash[:error] = e.message
        redirect_to PallasTrade.admin_ai_path
      end

      private

      def add_ai_sub_breadcrumb
        case action_name
        when 'providers'
          add_breadcrumb PallasTrade.t(:providers), PallasTrade.admin_ai_providers_path
        when 'provider'
          add_breadcrumb PallasTrade.t(:providers), PallasTrade.admin_ai_providers_path
          provider = find_provider
          add_breadcrumb provider.name, PallasTrade.admin_ai_provider_path(provider)
        when 'models'
          add_breadcrumb PallasTrade.t(:models), PallasTrade.admin_ai_models_path
        when 'capabilities'
          add_breadcrumb PallasTrade.t(:capabilities), PallasTrade.admin_ai_capabilities_path
        when 'runs'
          add_breadcrumb PallasTrade.t(:runs), PallasTrade.admin_ai_runs_path
        end
      end

      def provision_models_for_all_providers
        current_store.ai_providers.where(type: PROVIDER_TYPES).find_each do |provider|
          PallasTrade::AI::ProvisionModels.call(provider: provider)
        end
      end

      def find_provider
        current_store.ai_providers.find_by_prefix_id!(params[:id]).tap do |provider|
          unless PROVIDER_TYPES.include?(provider.type)
            raise ActiveRecord::RecordNotFound, "Not an AI provider"
          end
        end
      end

      def load_providers
        @providers = current_store.ai_providers.where(type: PROVIDER_TYPES)
      end

      def load_models
        @models = PallasTrade::AI::Model.where(store: current_store).includes(:provider).order(:name)
      end

      def load_runs
        @runs = PallasTrade::AI::Run.where(store: current_store).recent
      end

      def load_capabilities
        @capabilities = PallasTrade::AI.capabilities.all.map do |entry|
          setting = PallasTrade::AI::CapabilitySetting.find_by(store: current_store, capability_key: entry.key)
          { entry: entry, setting: setting }
        end
      end

    end
  end
end
