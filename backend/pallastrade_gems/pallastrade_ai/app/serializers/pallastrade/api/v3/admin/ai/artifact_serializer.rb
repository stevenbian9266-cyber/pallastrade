# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          class ArtifactSerializer < PallasTrade::Api::V3::BaseSerializer
            attributes :id, :kind, :schema_version, :content_type,
                       :checksum, :created_at, :updated_at

            one :run, resource: 'PallasTrade::Api::V3::Admin::AI::RunSerializer'

            attribute :payload do |artifact|
              artifact.payload
            end
          end
        end
      end
    end
  end
end
