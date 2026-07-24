module PallasTradeAdyen
  class Engine < Rails::Engine
    require 'pallastrade/core'
    isolate_namespace PallasTrade
    engine_name 'pallastrade_adyen'

    Environment = Struct.new(:event_handlers, :events, :hmac_validators)

    config.eager_load_paths += %W(#{config.root}/app/services)

    config.generators do |g| # use rspec for tests
      g.test_framework :rspec
    end

    initializer 'pallastrade_adyen.environment', before: :load_config_initializers do |app|
      app.config.pallastrade_adyen = Environment.new
      app.config.pallastrade_adyen.event_handlers = {}
      app.config.pallastrade_adyen.events = {}
      app.config.pallastrade_adyen.hmac_validators = {}
      PallasTradeAdyen::Config = PallasTradeAdyen::Configuration.new
    end

    config.after_initialize do
      Rails.application.config.pallastrade_adyen.event_handlers.merge!(
        'AUTHORISATION' => PallasTradeAdyen::Webhooks::ProcessAuthorisationEventJob,
        'CAPTURE' => PallasTradeAdyen::Webhooks::ProcessCaptureEventJob,
        'CANCELLATION' => PallasTradeAdyen::Webhooks::ProcessCancellationEventJob
      )

      Rails.application.config.pallastrade_adyen.events.merge!(
        'AUTHORISATION' => PallasTradeAdyen::Webhooks::Event,
        'CAPTURE' => PallasTradeAdyen::Webhooks::Event,
        'CANCELLATION' => PallasTradeAdyen::Webhooks::Event
      )

      Rails.application.config.pallastrade_adyen.hmac_validators.merge!(
        'AUTHORISATION' => PallasTradeAdyen::Webhooks::StandardHmacValidator,
        'CAPTURE' => PallasTradeAdyen::Webhooks::StandardHmacValidator,
        'CANCELLATION' => PallasTradeAdyen::Webhooks::StandardHmacValidator
      )
    end

    def self.activate
      glob_paths = [File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')]

      glob_paths.each do |glob_path|
        Dir.glob(glob_path) do |c|
          Rails.configuration.cache_classes ? require(c) : load(c)
        end
      end
    end

    config.to_prepare(&method(:activate).to_proc)
  end
end
