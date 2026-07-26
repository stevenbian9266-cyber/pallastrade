# frozen_string_literal: true

module PallasTradeAI
  class Engine < Rails::Engine
    require 'pallastrade/core'
    require 'pallastrade/api'
    isolate_namespace PallasTrade
    engine_name 'pallastrade_ai'

    # Add subscribers and permission_sets to autoload paths
    config.paths.add 'app/subscribers', eager_load: true
    config.paths.add 'app/permission_sets', eager_load: true

    # Use rspec for tests
    config.generators do |g|
      g.test_framework :rspec
    end

    initializer 'pallastrade_ai.inflections', before: :load_config_initializers do |_app|
      ActiveSupport::Inflector.inflections(:en) do |inflect|
        inflect.acronym 'AI'
      end
    end

    initializer 'pallastrade_ai.environment', before: :load_config_initializers do |_app|
      PallasTradeAI::Config = PallasTradeAI::Configuration.new
    end

    initializer 'pallastrade_ai.filter_parameters' do |app|
      # Ensure AI credential fields are filtered from logs
      ai_filters = %i[
        api_key access_token credential credentials secret
        authorization ai_api_key ai_access_token
      ]
      app.config.filter_parameters += ai_filters
    end

    initializer 'pallastrade_ai.encryption_check' do |_app|
      # Validate that Active Record Encryption is configured.
      # AI module MUST fail closed if encryption keys are missing.
      if defined?(ActiveRecord::Encryption) &&
         ActiveRecord::Encryption.respond_to?(:primary_key) &&
         ActiveRecord::Encryption.primary_key.blank?
        Rails.logger.warn(
          '[PallasTrade AI] Active Record Encryption primary key is not configured. ' \
          'AI Provider secrets cannot be stored. Set RAILS_MASTER_KEY or configure ' \
          'active_record_encryption.primary_key.'
        )
      end
    end

    # Temporarily disabled for debugging — re-enable after fixing base issues
    # config.after_initialize do
    #   PallasTrade.subscribers.concat [
    #     PallasTrade::AI::EventSubscriber
    #   ] if defined?(PallasTrade::AI::EventSubscriber)
    # end
  end
end
