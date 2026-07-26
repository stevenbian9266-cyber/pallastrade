# frozen_string_literal: true

module PallasTrade
  module AI
    module PermissionSets
      # Permission set for AI configuration management.
      # Grants ability to manage AI settings, providers, models, and capabilities.
      class ConfigurationManagement
        def self.rules
          [
            { action: :manage, subject: 'PallasTrade::AI::Setting' },
            { action: :manage, subject: 'PallasTrade::AI::ProviderSecret' },
            { action: :manage, subject: 'PallasTrade::AI::Model' },
            { action: :manage, subject: 'PallasTrade::AI::CapabilitySetting' },
            { action: :manage, subject: 'PallasTrade::AI::Integrations::DeepSeek' },
            { action: :manage, subject: 'PallasTrade::AI::Integrations::OpenAI' }
          ]
        end

        def self.display_name
          'AI Configuration Management'
        end

        def self.description
          'Manage AI providers, models, and capability settings'
        end
      end

      # Permission set for AI usage display.
      # Grants read-only access to runs, artifacts, and usage data.
      class UsageDisplay
        def self.rules
          [
            { action: :read, subject: 'PallasTrade::AI::Run' },
            { action: :read, subject: 'PallasTrade::AI::Artifact' }
          ]
        end

        def self.display_name
          'AI Usage Display'
        end

        def self.description
          'View AI run history, artifacts, and usage metrics'
        end
      end
    end
  end
end
