# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        module AI
          class RunSerializer < PallasTrade::Api::V3::BaseSerializer
            attributes :id, :capability_key, :capability_version,
                       :provider_type, :provider_model_id,
                       :status, :mode, :unavailable_reason,
                       :fallback_from_model_id,
                       :prompt_key, :prompt_version,
                       :input_schema_version, :output_schema_version,
                       :input_digest, :idempotency_key, :safe_parameters,
                       :provider_request_id,
                       :input_tokens, :cached_input_tokens,
                       :output_tokens, :reasoning_tokens,
                       :estimated_cost, :pricing_snapshot,
                       :latency_ms, :attempts,
                       :error_code, :error_message,
                       :queued_at, :started_at, :completed_at,
                       :expires_at, :created_at, :updated_at

            one :store, resource: 'PallasTrade::Api::V3::StoreSerializer'
            one :user, resource: 'PallasTrade::Api::V3::AdminUserSerializer'
            one :provider, resource: 'PallasTrade::Api::V3::Admin::AI::ProviderSerializer'
            one :model, resource: 'PallasTrade::Api::V3::Admin::AI::ModelSerializer'
            many :artifacts, resource: 'PallasTrade::Api::V3::Admin::AI::ArtifactSerializer'
          end
        end
      end
    end
  end
end
