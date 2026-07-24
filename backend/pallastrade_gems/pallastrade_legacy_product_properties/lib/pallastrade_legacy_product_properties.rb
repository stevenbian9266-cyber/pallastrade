require 'pallastrade'
require 'pallastrade_legacy_product_properties/engine'
require 'pallastrade_legacy_product_properties/version'
require 'pallastrade_legacy_product_properties/configuration'

module PallasTradeLegacyProductProperties
  mattr_accessor :queue

  def self.queue
    @@queue ||= PallasTrade.queues.default
  end
end
