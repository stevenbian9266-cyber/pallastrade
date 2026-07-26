# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # GET    /api/v3/admin/ai/capability_settings 鈥?list capability settings for store
          # PATCH  /api/v3/admin/ai/capability_settings/:id 鈥?update a capability setting
          class CapabilitySettingsController < BaseController
            def index
              authorize! :show, PallasTrade::AI::CapabilitySetting
              settings = PallasTrade::AI::CapabilitySetting.where(store: current_store)
              render json: serialize_resources(settings)
            end

            def update
              setting = PallasTrade::AI::CapabilitySetting.where(store: current_store).find(params[:id])
              authorize! :update, setting

              if setting.update(setting_params)
                render json: serialize_resource(setting)
              else
                render_validation_error(setting.errors)
              end
            end

            private

            def setting_params
              params.require(:capability_setting).permit(
                :active, :primary_model_id, :fallback_model_id,
                :fallback_enabled, :daily_request_limit, :daily_token_limit,
                parameter_overrides: {}
              )
            end
          end
        end
      end
    end
  end
end
