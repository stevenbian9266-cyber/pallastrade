require 'rails/engine'

require_relative 'dependencies'
require_relative 'configuration'

module PallasTrade
  module Api
    class Engine < Rails::Engine
      isolate_namespace PallasTrade
      engine_name 'pallastrade_api'

      initializer 'PallasTrade.api.environment', before: :load_config_initializers do |_app|
        PallasTrade::Api::Config = PallasTrade::Api::Configuration.new
        PallasTrade::Api::Dependencies = PallasTrade::Api::ApiDependencies.new
      end

      initializer 'PallasTrade.api.request_size_limit' do |app|
        require_relative 'middleware/request_size_limit'
        app.middleware.insert_before Rack::Runtime, PallasTrade::Api::Middleware::RequestSizeLimit
      end

      # Add API event subscribers
      config.after_initialize do
        PallasTrade.subscribers << PallasTrade::WebhookEventSubscriber
      end

      # Warn in production if no dedicated JWT secret key is configured
      config.after_initialize do
        next unless Rails.env.production?

        if PallasTrade::Api::Config[:jwt_secret_key].blank? &&
           Rails.application.credentials.jwt_secret_key.blank? &&
           ENV['JWT_SECRET_KEY'].blank?
          Rails.logger.warn(
            '[Spree] No dedicated JWT secret key configured. Falling back to Rails.application.secret_key_base. ' \
            'Set PallasTrade::Api::Config[:jwt_secret_key], Rails credentials jwt_secret_key, or ENV["JWT_SECRET_KEY"] ' \
            'for improved security.'
          )
        end
      end

      def self.root
        @root ||= Pathname.new(File.expand_path('../../..', __dir__))
      end
    end
  end
end
