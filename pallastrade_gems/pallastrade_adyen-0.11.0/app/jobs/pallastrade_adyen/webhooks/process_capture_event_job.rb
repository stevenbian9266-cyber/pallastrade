module PallasTradeAdyen
  module Webhooks
    class ProcessCaptureEventJob < PallasTradeAdyen::BaseJob
      def perform(payload)
        event = PallasTradeAdyen::Webhooks::Event.new(event_data: payload)
        PallasTradeAdyen::Webhooks::EventProcessors::CaptureEventProcessor.new(event).call
      end
    end
  end
end
