# frozen_string_literal: true

module PallasTrade
  module AI
    # Provisions catalog (built-in) model configurations for a provider.
    #
    # When a provider is first configured, its recommended models from the
    # provider registry catalog should be auto-created as store-scoped Model
    # records — inactive by default, so the admin can review and enable them.
    #
    # This service is idempotent: existing models matched by (provider_id,
    # provider_model_id) are never overwritten, and only missing catalog
    # entries are created.
    #
    # @example
    #   provider = current_store.ai_providers.find_by(type: 'PallasTrade::AI::Provider::DeepSeek')
    #   PallasTrade::AI::ProvisionModels.call(provider: provider)
    class ProvisionModels
      def self.call(provider:)
        new(provider).call
      end

      def initialize(provider)
        @provider = provider
      end

      def call
        entry = PallasTrade::AI.providers[provider_key]
        return if entry.nil? || entry.recommended_models.blank?

        position = existing_max_position

        entry.recommended_models.each do |catalog_model|
          next if model_exists?(catalog_model[:provider_model_id])

          position += 1
          create_model!(catalog_model, position)
        end
      end

      private

      def provider_key
        @provider_key ||= @provider.key.to_sym
      end

      def existing_max_position
        PallasTrade::AI::Model.where(provider: @provider).maximum(:position) || 0
      end

      def model_exists?(provider_model_id)
        PallasTrade::AI::Model.exists?(
          provider: @provider,
          provider_model_id: provider_model_id
        )
      end

      def create_model!(catalog_model, position)
        PallasTrade::AI::Model.create!(
          store: @provider.store,
          provider: @provider,
          name: catalog_model[:name],
          provider_model_id: catalog_model[:provider_model_id],
          kind: catalog_model[:kind] || 'text',
          active: false,
          built_in: true,
          capabilities: catalog_model[:capabilities] || [],
          default_parameters: catalog_model[:default_parameters] || {},
          position: position
        )
      end
    end
  end
end
