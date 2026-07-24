module PallasTrade
  module Webhooks
    def self.disable_webhooks
      PallasTrade::Deprecation.warn('PallasTrade::Webhooks.disable_webhooks is deprecated and will be removed in PallasTrade 5.5. Use PallasTrade::LegacyWebhooks.disable_webhooks instead.')
      prev_value = disabled?
      Thread.current[:disable_pallastrade_legacy_webhooks] = true
      yield
    ensure
      Thread.current[:disable_pallastrade_legacy_webhooks] = prev_value
    end

    def self.disabled?
      PallasTrade::Deprecation.warn('PallasTrade::Webhooks.disabled? is deprecated and will be removed in PallasTrade 5.5. Use PallasTrade::LegacyWebhooks.disabled? instead.')
      !!Thread.current[:disable_pallastrade_legacy_webhooks]
    end

    def self.disabled=(value)
      PallasTrade::Deprecation.warn('PallasTrade::Webhooks.disabled= is deprecated and will be removed in PallasTrade 5.5. Use PallasTrade::LegacyWebhooks.disabled= instead.')
      Thread.current[:disable_pallastrade_legacy_webhooks] = value
    end
  end
end
