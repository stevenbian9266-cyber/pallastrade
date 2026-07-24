module PallasTradeLegacyProductProperties
  class Engine < Rails::Engine
    require 'pallastrade/core'
    isolate_namespace PallasTrade
    engine_name 'pallastrade_legacy_product_properties'

    config.generators do |g|
      g.test_framework :rspec
    end

    initializer 'pallastrade_legacy_product_properties.environment', before: :load_config_initializers do |_app|
      PallasTradeLegacyProductProperties::Config = PallasTradeLegacyProductProperties::Configuration.new
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare(&method(:activate).to_proc)
  end
end
