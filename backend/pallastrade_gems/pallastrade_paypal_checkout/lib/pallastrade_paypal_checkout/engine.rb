module PallasTradePaypalCheckout
  class Engine < Rails::Engine
    require 'pallastrade/core'
    isolate_namespace PallasTrade
    engine_name 'pallastrade_paypal_checkout'

    # use rspec for tests
    config.generators do |g|
      g.test_framework :rspec
    end

    initializer 'pallastrade_paypal_checkout.environment', before: :load_config_initializers do |_app|
      PallasTradePaypalCheckout::Config = PallasTradePaypalCheckout::Configuration.new
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.after_initialize do
      activate
    end
  end
end
