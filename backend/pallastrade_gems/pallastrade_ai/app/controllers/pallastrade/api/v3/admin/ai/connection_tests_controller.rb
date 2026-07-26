# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # POST /api/v3/admin/ai/providers/:provider_id/connection_tests
          class ConnectionTestsController < BaseController
            def create
              provider = find_provider
              authorize! :update, provider

              entry = PallasTrade::AI.providers[provider.key.to_sym]
              unless entry
                return render_error(code: 'invalid_provider_type', message: 'Unknown provider type', status: :unprocessable_entity)
              end

              adapter = entry.adapter_class.constantize.new
              result = adapter.test_connection(provider)

              # Update verification timestamp
              provider.update!(
                last_verified_at: Time.current,
                verification_status: result[:status]
              )

              render json: {
                data: {
                  success: result[:success],
                  status: result[:status],
                  latency_ms: result[:latency_ms],
                  error: result[:error]
                }
              }
            rescue PallasTrade::AI::Errors::CredentialsError => e
              render_error(code: 'ai_credentials_missing', message: e.message, status: :unprocessable_entity)
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
