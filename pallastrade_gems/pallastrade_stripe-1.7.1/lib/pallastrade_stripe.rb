require 'pallastrade_core'
require 'pallastrade_stripe/engine'
require 'pallastrade_stripe/version'
require 'pallastrade_stripe/configuration'

require 'stripe'
require 'stripe_event'

module SpreeStripe
  mattr_accessor :queue

  def self.queue
    @@queue ||= PallasTrade.queues.default
  end
end
