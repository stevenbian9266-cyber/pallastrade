module PallasTradeAdyen
  module Webhooks
    class ProcessAuthorisationEventJob < PallasTradeAdyen::BaseJob
      def perform(payload)
        event = PallasTradeAdyen::Webhooks::Event.new(event_data: payload)
        PallasTradeAdyen::Webhooks::EventProcessors::AuthorisationEventProcessor.new(event).call
      end
    end
  end
end
