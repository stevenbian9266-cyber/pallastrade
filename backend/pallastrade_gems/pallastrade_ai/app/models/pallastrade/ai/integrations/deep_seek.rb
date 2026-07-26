# frozen_string_literal: true

module PallasTrade
  module AI
    module Integrations
      # DeepSeek provider integration.
      # Inherits from PallasTrade::Integration (STI).
      # One per store maximum (enforced by Integration uniqueness on store+type).
      class DeepSeek < PallasTrade::Integration
        # Provider type key used in the registry.
        PROVIDER_KEY = :deepseek

        # Non-sensitive settings stored in preferences.
        preference :base_url, :string, default: 'https://api.deepseek.com'
        preference :open_timeout_seconds, :integer, default: 5
        preference :read_timeout_seconds, :integer, default: 60
        preference :max_retries, :integer, default: 2
        preference :concurrency_limit, :integer, default: 5

        # The provider secret is managed through PallasTrade::AI::ProviderSecret.
        has_one :ai_provider_secret,
                class_name: 'PallasTrade::AI::ProviderSecret',
                foreign_key: :integration_id,
                dependent: :destroy

        validates :store, uniqueness: { scope: :type }, if: -> { type == 'PallasTrade::AI::Integrations::DeepSeek' }

        def self.integration_name
          'DeepSeek'
        end

        def self.integration_key
          'deepseek'
        end

        def can_connect?
          ai_provider_secret&.configured? && active?
        end

        # Retrieve the decrypted API key for internal use.
        # Must only be called within service objects 鈥?never exposed to API.
        def decrypted_api_key
          secret = ai_provider_secret
          raise PallasTrade::AI::Errors::CredentialsError, 'No credentials configured' unless secret&.configured?

          secret.credentials
        end
      end
    end
  end
end
