# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # DELETE /api/v3/admin/ai/providers/:provider_id/credential
          class CredentialsController < BaseController
            def destroy
              provider = find_provider
              authorize! :update, provider

              secret = PallasTrade::AI::ProviderSecret.find_by(integration: provider)
              if secret
                secret.destroy!
                provider.update!(active: false)
              end

              render json: serialize_resource(provider)
            end

            private

            def find_provider
              current_store.integrations.find_by!(
                id: params[:provider_id],
                type: %w[PallasTrade::AI::Integrations::DeepSeek PallasTrade::AI::Integrations::OpenAI]
              )
            end
          end
        end
      end
    end
  end
end
