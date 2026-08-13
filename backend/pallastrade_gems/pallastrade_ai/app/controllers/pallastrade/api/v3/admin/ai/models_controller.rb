# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # CRUD for AI model configurations under a provider.
          class ModelsController < BaseController
            def index
              authorize! :show, PallasTrade::AI::Model

              # Lazy provisioning: ensure catalog models exist for every provider.
              current_store.ai_providers.where(
                type: %w[PallasTrade::AI::Provider::DeepSeek PallasTrade::AI::Provider::OpenAI]
              ).find_each do |provider|
                PallasTrade::AI::ProvisionModels.call(provider: provider)
              end

              models = PallasTrade::AI::Model.where(store: current_store)
              models = models.where(provider_id: params[:provider_id]) if params[:provider_id].present?
              render json: serialize_resources(models)
            end

            def show
              model = find_model
              authorize! :show, model
              render json: serialize_resource(model)
            end

            def create
              authorize! :create, PallasTrade::AI::Model

              provider = current_store.ai_providers.find_by(id: params[:provider_id])
              return render_error(code: 'invalid_provider', message: 'Provider not found', status: :not_found) unless provider

              model = PallasTrade::AI::Model.new(model_params.merge(store: current_store, provider: provider))
              model.built_in = false # Custom models are not built-in

              if model.save
                render json: serialize_resource(model), status: :created
              else
                render_validation_error(model.errors)
              end
            end

            def update
              model = find_model
              authorize! :update, model

              if model.update(model_params)
                render json: serialize_resource(model)
              else
                render_validation_error(model.errors)
              end
            end

            def destroy
              model = find_model
              authorize! :destroy, model

              # Check if model is referenced by capability settings
              refs = PallasTrade::AI::CapabilitySetting.where(primary_model_id: model.id).or(
                PallasTrade::AI::CapabilitySetting.where(fallback_model_id: model.id)
              )
              if refs.exists?
                return render_error(
                  code: 'model_in_use',
                  message: 'Model is referenced by capability settings. Unmap it first.',
                  status: :conflict
                )
              end

              model.destroy!
              head :no_content
            end

            private

            def find_model
              PallasTrade::AI::Model.where(store: current_store).find(params[:id])
            end

            def model_params
              params.require(:model).permit(
                :name, :provider_model_id, :kind, :active,
                :catalog_version, :position,
                capabilities: [], default_parameters: {}
              )
            end
          end
        end
      end
    end
  end
end
