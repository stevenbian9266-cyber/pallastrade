# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # CRUD for AI provider configurations (DeepSeek, OpenAI, etc.).
          # Providers are store-scoped PallasTrade::AI::Provider STI records.
          class ProvidersController < BaseController
            PROVIDER_TYPES = %w[
              PallasTrade::AI::Provider::DeepSeek
              PallasTrade::AI::Provider::OpenAI
            ].freeze

            def index
              authorize! :show, PallasTrade::AI::Provider

              # Lazy provisioning: ensure every registered provider type has
              # a store-scoped Provider record so the UI always shows
              # preset cards (DeepSeek, OpenAI) with "not configured" status.
              PallasTrade::AI::ProvisionProviders.call(store: current_store)

              providers = current_store.ai_providers.where(type: PROVIDER_TYPES)
              render json: serialize_resources(providers)
            end

            def show
              provider = find_provider
              authorize! :show, provider
              render json: serialize_resource(provider)
            end

            def create
              authorize! :create, PallasTrade::AI::Provider

              provider_type = params[:provider_type]&.to_sym
              entry = PallasTrade::AI.providers[provider_type]
              return render_error(code: 'invalid_provider_type', message: "Unknown provider type: #{provider_type}", status: :unprocessable_entity) unless entry

              # provider_class 来自代码级 ProviderRegistry 白名单（entry 已校验）。
              # 反射封装在 registry#provider_class_for 内（避免 Brakeman UnsafeReflection）。
              klass = PallasTrade::AI.providers.provider_class_for(provider_type)
              return render_error(code: 'invalid_provider_type', message: "Unknown provider type: #{provider_type}", status: :unprocessable_entity) unless klass
              provider = klass.new(store: current_store, active: false)

              # Set non-secret preferences（白名单：仅允许 preference DSL 声明的键）
              if params[:preferences].present?
                allowed = provider.class.defined_preferences
                params[:preferences].permit(*allowed).each do |key, value|
                  provider.public_send(:"preferred_#{key}=", value)
                end
              end

              ActiveRecord::Base.transaction do
                provider.save!

                # Store API key if provided
                if params[:api_key].present?
                  secret = PallasTrade::AI::ProviderSecret.new(provider: provider)
                  secret.credentials = params[:api_key]
                  secret.save!
                end
              end

              render json: serialize_resource(provider), status: :created
            rescue ActiveRecord::RecordInvalid => e
              render_validation_error(e.record.errors)
            end

            def update
              provider = find_provider
              authorize! :update, provider

              ActiveRecord::Base.transaction do
                if params[:active].present?
                  provider.update!(active: params[:active])
                end

                if params[:preferences].present?
                  allowed = provider.class.defined_preferences
                  params[:preferences].permit(*allowed).each do |key, value|
                    provider.public_send(:"preferred_#{key}=", value)
                  end
                  provider.save!
                end

                # Replace API key (if new key provided)
                if params[:api_key].present? && !params[:api_key].blank?
                  secret = PallasTrade::AI::ProviderSecret.find_or_initialize_by(provider: provider)
                  secret.credentials = params[:api_key]
                  secret.save!
                end

                # Clear credential (if explicitly requested)
                if params[:clear_credential].present? && ActiveModel::Type::Boolean.new.cast(params[:clear_credential])
                  secret = PallasTrade::AI::ProviderSecret.find_by(provider: provider)
                  secret&.destroy!
                  provider.update!(active: false)
                end
              end

              render json: serialize_resource(provider)
            rescue ActiveRecord::RecordInvalid => e
              render_validation_error(e.record.errors)
            end

            def destroy
              provider = find_provider
              authorize! :destroy, provider

              # Check if any capability settings reference this provider's models
              model_ids = PallasTrade::AI::Model.where(provider: provider).pluck(:id)
              active_refs = PallasTrade::AI::CapabilitySetting.where(primary_model_id: model_ids).or(
                PallasTrade::AI::CapabilitySetting.where(fallback_model_id: model_ids)
              ).exists?

              if active_refs
                return render_error(
                  code: 'provider_in_use',
                  message: 'Provider has models referenced by capability settings. Unmap them first.',
                  status: :conflict
                )
              end

              ActiveRecord::Base.transaction do
                PallasTrade::AI::ProviderSecret.where(provider: provider).destroy_all
                PallasTrade::AI::Model.where(provider: provider).destroy_all
                provider.destroy!
              end

              head :no_content
            end

            private

            def find_provider
              current_store.ai_providers.find_by!(
                id: params[:id],
                type: PROVIDER_TYPES
              )
            end
          end
        end
      end
    end
  end
end
