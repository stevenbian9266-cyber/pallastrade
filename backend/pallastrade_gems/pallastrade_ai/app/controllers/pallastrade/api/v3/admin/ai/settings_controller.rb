# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # GET  /api/v3/admin/ai/settings 鈥?show store AI settings
          # PATCH /api/v3/admin/ai/settings 鈥?update store AI settings
          class SettingsController < BaseController
            def show
              authorize! :show, ai_setting
              render json: serialize_resource(ai_setting)
            end

            def update
              authorize! :update, ai_setting

              if ai_setting.update(setting_params)
                render json: serialize_resource(ai_setting)
              else
                render_validation_error(ai_setting.errors)
              end
            end

            private

            def setting_params
              params.require(:setting).permit(
                :active, :default_model_id, :fallback_enabled,
                :daily_request_limit, :daily_input_token_limit,
                :daily_output_token_limit, :daily_cost_limit,
                :run_retention_days, :content_logging_mode
              )
            end
          end
        end
      end
    end
  end
end
