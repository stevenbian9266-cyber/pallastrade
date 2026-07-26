# frozen_string_literal: true

module PallasTrade
  module AI
    extend ActiveSupport::Autoload

    # Registries are loaded lazily 鈥?they don't depend on base_class or DB.
    autoload :ProviderRegistry, 'pallastrade/ai/provider_registry'
    autoload :CapabilityRegistry, 'pallastrade/ai/capability_registry'
    autoload :Errors, 'pallastrade/ai/errors'
    autoload :BaseModel, 'pallastrade/ai/base_model'

    # Provider Registry — holds registered provider types, adapters, and catalogs.
    # This is a code-level registry; not a database table.
    mattr_accessor :providers do
      PallasTrade::AI::ProviderRegistry.new
    end

    # Capability Registry 鈥?holds registered business capabilities.
    mattr_accessor :capabilities do
      PallasTrade::AI::CapabilityRegistry.new
    end

    # Error codes for stable API responses.
    ERROR_CODES = {
      ai_disabled: 'ai_disabled',
      ai_provider_disabled: 'ai_provider_disabled',
      ai_model_disabled: 'ai_model_disabled',
      ai_capability_disabled: 'ai_capability_disabled',
      ai_credentials_missing: 'ai_credentials_missing',
      ai_credentials_invalid: 'ai_credentials_invalid',
      ai_configuration_invalid: 'ai_configuration_invalid',
      ai_model_incompatible: 'ai_model_incompatible',
      ai_budget_exceeded: 'ai_budget_exceeded',
      ai_rate_limited: 'ai_rate_limited',
      ai_provider_unavailable: 'ai_provider_unavailable',
      ai_output_invalid: 'ai_output_invalid',
      ai_run_conflict: 'ai_run_conflict',
      ai_permission_denied: 'ai_permission_denied'
    }.freeze

    # Check if a capability is available for a given store/actor/resource.
    # No side effects 鈥?does not create a Run or call external provider.
    #
    # @param capability [String] capability key
    # @param store [PallasTrade::Store]
    # @param actor [PallasTrade::AdminUser, nil]
    # @param resource [Object, nil]
    # @return [Hash] { available: Boolean, reason: String, details: Hash }
    def self.available?(capability:, store:, actor: nil, resource: nil)
      PallasTrade::AI::AvailabilityService.check(
        capability: capability,
        store: store,
        actor: actor,
        resource: resource
      )
    end
  end
end
