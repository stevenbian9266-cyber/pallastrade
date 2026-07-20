module PallasTradeAdyen
  module Webhooks
    class ProcessCancellationEventJob < PallasTradeAdyen::BaseJob
      def perform(payload)
        event = PallasTradeAdyen::Webhooks::Event.new(event_data: payload)
        PallasTradeAdyen::Webhooks::EventProcessors::CancellationEventProcessor.new(event).call
      end
    end
  end
end
