# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          class SettingSerializer < PallasTrade::Api::V3::BaseSerializer
            attributes :id, :active, :fallback_enabled,
                       :daily_request_limit, :daily_input_token_limit,
                       :daily_output_token_limit, :daily_cost_limit,
                       :run_retention_days, :content_logging_mode,
                       :created_at, :updated_at

            one :store, resource: 'PallasTrade::Api::V3::StoreSerializer'
            one :default_model, resource: 'PallasTrade::Api::V3::Admin::AI::ModelSerializer'
          end
        end
      end
    end
  end
end
