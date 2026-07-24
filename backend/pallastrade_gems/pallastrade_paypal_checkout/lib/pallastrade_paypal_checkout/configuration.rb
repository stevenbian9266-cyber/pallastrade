module PallasTradePaypalCheckout
  class Configuration < PallasTrade::Preferences::Configuration
    preference :use_legacy_api, :boolean, default: false
  end
end
