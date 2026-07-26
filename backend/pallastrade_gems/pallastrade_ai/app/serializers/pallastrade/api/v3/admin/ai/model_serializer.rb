# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          class ModelSerializer < PallasTrade::Api::V3::BaseSerializer
            attributes :id, :name, :provider_model_id, :kind, :active,
                       :built_in, :catalog_version, :capabilities,
                       :default_parameters, :position, :created_at, :updated_at

            one :store, resource: 'PallasTrade::Api::V3::StoreSerializer'
            one :provider, resource: 'PallasTrade::Api::V3::Admin::AI::ProviderSerializer'

            attribute :capability_count do |model|
              PallasTrade::AI::CapabilitySetting.where(primary_model_id: model.id)
                                                .or(PallasTrade::AI::CapabilitySetting.where(fallback_model_id: model.id))
                                                .count
            end

            attribute :last_used_at do |model|
              PallasTrade::AI::Run.where(model_id: model.id).maximum(:created_at)&.iso8601
            end
          end
        end
      end
    end
  end
end
