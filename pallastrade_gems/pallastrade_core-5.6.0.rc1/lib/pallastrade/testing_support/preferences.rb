module PallasTrade
  module TestingSupport
    module Preferences
      # Resets all preferences to default values, you can
      # pass a block to override the defaults with a block
      #
      # reset_PALLASTRADE_preferences do |config|
      #   config.track_inventory_levels = false
      # end
      #
      def reset_PALLASTRADE_preferences(&config_block)
        config = Rails.application.config.spree.preferences.reset
        configure_PALLASTRADE_preferences &config_block if block_given?
      end

      def configure_PALLASTRADE_preferences
        config = Rails.application.config.spree.preferences
        yield(config) if block_given?
      end

      def assert_preference_unset(preference)
        find("#preferences_#{preference}")['checked'].should be false
        PallasTrade::Config[preference].should be false
      end
    end
  end
end
