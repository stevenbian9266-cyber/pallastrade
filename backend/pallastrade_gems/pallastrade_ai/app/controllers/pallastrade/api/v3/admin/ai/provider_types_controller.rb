# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # GET /api/v3/admin/ai/provider_types 鈥?list registered provider types
          class ProviderTypesController < BaseController
            def index
              authorize! :show, PallasTrade::AI::Setting

              types = PallasTrade::AI.providers.all.map do |entry|
                {
                  key: entry.key,
                  display_name: entry.display_name,
                  default_base_url: entry.default_base_url,
                  secret_fields: entry.secret_fields,
                  non_secret_settings: entry.non_secret_settings,
                  supported_parameters: entry.supported_parameters,
                  supported_capabilities: entry.supported_capabilities,
                  recommended_models: entry.recommended_models
                }
              end

              render json: { data: types }
            end
          end
        end
      end
    end
  end
end
