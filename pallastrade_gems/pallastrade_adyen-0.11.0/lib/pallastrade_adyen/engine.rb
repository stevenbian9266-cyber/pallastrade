module SpreeAdyen
  class Engine < Rails::Engine
    require 'pallastrade/core'
    isolate_namespace PallasTrade
    engine_name 'pallastrade_adyen'

    Environment = Struct.new(:event_handlers, :events, :hmac_validators)

    config.eager_load_paths += %W(#{config.root}/app/services)

    # Only load API v2 controllers and serializers when PALLASTRADE_legacy_api_v2 gem is available
    if defined?(SpreeLegacyApiV2::Engine)
      config.autoload_paths << root.join('lib', 'pallastrade_api_v2')
      config.eager_load_paths << root.join('lib', 'pallastrade_api_v2')
    end

    config.generators do |g| # use rspec for tests
      g.test_framework :rspec
    end

    initializer 'pallastrade_adyen.environment', before: :load_config_initializers do |app|
      app.config.PALLASTRADE_adyen = Environment.new
      app.config.PALLASTRADE_adyen.event_handlers = {}
      app.config.PALLASTRADE_adyen.events = {}
      app.config.PALLASTRADE_adyen.hmac_validators = {}
      SpreeAdyen::Config = SpreeAdyen::Configuration.new
    end

    config.after_initialize do
      Rails.application.config.PALLASTRADE_adyen.event_handlers.merge!(
        'AUTHORISATION' => SpreeAdyen::Webhooks::ProcessAuthorisationEventJob,
        'CAPTURE' => SpreeAdyen::Webhooks::ProcessCaptureEventJob,
        'CANCELLATION' => SpreeAdyen::Webhooks::ProcessCancellationEventJob
      )

      Rails.application.config.PALLASTRADE_adyen.events.merge!(
        'AUTHORISATION' => SpreeAdyen::Webhooks::Event,
        'CAPTURE' => SpreeAdyen::Webhooks::Event,
        'CANCELLATION' => SpreeAdyen::Webhooks::Event
      )

      Rails.application.config.PALLASTRADE_adyen.hmac_validators.merge!(
        'AUTHORISATION' => SpreeAdyen::Webhooks::StandardHmacValidator,
        'CAPTURE' => SpreeAdyen::Webhooks::StandardHmacValidator,
        'CANCELLATION' => SpreeAdyen::Webhooks::StandardHmacValidator
      )
    end

    initializer 'pallastrade_adyen.assets' do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.paths << root.join('app/javascript')
        app.config.assets.paths << root.join('vendor/javascript')
        app.config.assets.paths << root.join('vendor/stylesheets')
        app.config.assets.precompile += %w[PALLASTRADE_adyen_manifest]
      end
    end

    initializer 'pallastrade_adyen.importmap', before: 'importmap' do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << root.join('config/importmap.rb')
        # https://github.com/rails/importmap-rails?tab=readme-ov-file#sweeping-the-cache-in-development-and-test
        app.config.importmap.cache_sweepers << root.join('app/javascript')
      end
    end

    def self.activate
      glob_paths = [File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')]
      glob_paths << File.join(File.dirname(__FILE__), '../../lib/PALLASTRADE_api_v2/**/*_decorator*.rb') if defined?(SpreeLegacyApiV2::Engine)

      glob_paths.each do |glob_path|
        Dir.glob(glob_path) do |c|
          Rails.configuration.cache_classes ? require(c) : load(c)
        end
      end
    end

    config.after_initialize do
      activate
    end
  end
end
