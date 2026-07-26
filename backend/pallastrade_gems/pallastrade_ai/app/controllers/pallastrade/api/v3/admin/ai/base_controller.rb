# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          # Base controller for all AI admin endpoints.
          # Inherits from Admin::ResourceController for standard CRUD patterns.
          class BaseController < PallasTrade::Api::V3::Admin::ResourceController
            before_action :ensure_ai_accessible!

            private

            def ensure_ai_accessible!
              # System kill switch check 鈥?admins can still read configuration
              # but write operations are blocked.
              unless PallasTradeAI::Config.system_enabled?
                return if request.get? || request.head?

                render_error(
                  code: PallasTrade::AI::ERROR_CODES[:ai_disabled],
                  message: 'AI system is globally disabled',
                  status: :service_unavailable
                )
              end
            end

            def current_store
              @current_store ||= PallasTrade::Current.store
            end

            def ai_setting
              @ai_setting ||= PallasTrade::AI::Setting.find_or_initialize_by(store: current_store)
            end
          end
        end
      end
    end
  end
end
