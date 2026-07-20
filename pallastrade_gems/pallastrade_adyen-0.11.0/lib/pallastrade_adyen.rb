require 'pallastrade_core'
require 'pallastrade_adyen/engine'
require 'pallastrade_adyen/version'
require 'pallastrade_adyen/configuration'
require 'adyen-ruby-api-library'

module SpreeAdyen
  def self.queue
    'default'
  end

  def self.version
    VERSION
  end

  def self.event_handlers
    Rails.application.config.PALLASTRADE_adyen.event_handlers
  end

  def self.event_handlers=(value)
    Rails.application.config.PALLASTRADE_adyen.event_handlers = value
  end

  def self.events
    Rails.application.config.PALLASTRADE_adyen.events
  end

  def self.events=(value)
    Rails.application.config.PALLASTRADE_adyen.events = value
  end

  def self.hmac_validators
    Rails.application.config.PALLASTRADE_adyen.hmac_validators
  end

  def self.hmac_validators=(value)
    Rails.application.config.PALLASTRADE_adyen.hmac_validators = value
  end
end
