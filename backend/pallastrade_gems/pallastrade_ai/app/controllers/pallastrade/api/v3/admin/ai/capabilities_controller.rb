# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # GET /api/v3/admin/ai/capabilities 鈥?list registered capabilities
          class CapabilitiesController < BaseController
            def index
              authorize! :show, PallasTrade::AI::CapabilitySetting

              capabilities = PallasTrade::AI.capabilities.all.map do |entry|
                setting = PallasTrade::AI::CapabilitySetting.find_by(
                  store: current_store,
                  capability_key: entry.key
                )

                {
                  key: entry.key,
                  display_name: entry.display_name,
                  description: entry.description,
                  version: entry.version,
                  execution_mode: entry.execution_mode,
                  required_model_capabilities: entry.required_model_capabilities,
                  allowed_parameters: entry.allowed_parameters,
                  data_classification: entry.data_classification,
                  configured: setting.present?,
                  active: setting&.active? || false,
                  setting_id: setting&.id,
                  primary_model_id: setting&.primary_model_id,
                  fallback_model_id: setting&.fallback_model_id,
                  fallback_enabled: setting&.fallback_enabled || false
                }
              end

              render json: { data: capabilities }
            end
          end
        end
      end
    end
  end
end
