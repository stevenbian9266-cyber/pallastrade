# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          class CapabilitySettingSerializer < PallasTrade::Api::V3::BaseSerializer
            attributes :id, :capability_key, :active, :fallback_enabled,
                       :parameter_overrides, :daily_request_limit,
                       :daily_token_limit, :orphaned, :created_at, :updated_at

            one :store, resource: 'PallasTrade::Api::V3::StoreSerializer'
            one :primary_model, resource: 'PallasTrade::Api::V3::Admin::AI::ModelSerializer'
            one :fallback_model, resource: 'PallasTrade::Api::V3::Admin::AI::ModelSerializer'

            attribute :availability do |setting|
              if setting.orphaned?
                { available: false, reason: 'orphaned' }
              elsif !setting.active?
                { available: false, reason: 'capability_disabled' }
              elsif !setting.primary_model&.active?
                { available: false, reason: 'model_disabled' }
              elsif !setting.primary_model&.provider&.active?
                { available: false, reason: 'provider_disabled' }
              else
                { available: true, reason: nil }
              end
            end
          end
        end
      end
    end
  end
end
