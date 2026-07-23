module PallasTrade
  module Analytics
    def self.events
      @@supported_events ||= PallasTrade.analytics.events
    end

    def self.event_handlers
      @@event_handlers ||= PallasTrade.analytics.handlers
    end
  end
end
