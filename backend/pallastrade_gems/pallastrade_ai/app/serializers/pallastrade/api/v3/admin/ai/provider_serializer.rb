# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          class ProviderSerializer < PallasTrade::Api::V3::BaseSerializer
            attributes :id, :type, :active, :name, :key,
                       :preferences, :last_verified_at, :verification_status,
                       :created_at, :updated_at

            one :store, resource: 'PallasTrade::Api::V3::StoreSerializer'

            attribute :credential do |provider|
              secret = PallasTrade::AI::ProviderSecret.find_by(provider: provider)
              if secret
                secret.credential_summary
              else
                { credential_configured: false, credential_hint: '', credential_rotated_at: nil }
              end
            end

            attribute :connection_status do |provider|
              { verified_at: provider.last_verified_at&.iso8601, status: provider.verification_status || 'unverified' }
            end

            attribute :model_count do |provider|
              PallasTrade::AI::Model.where(provider: provider).count
            end

            attribute :active_model_count do |provider|
              PallasTrade::AI::Model.where(provider: provider, active: true).count
            end
          end
        end
      end
    end
  end
end
