# frozen_string_literal: true

module PallasTrade
  # Logs all PallasTrade events to Rails logger.
  #
  # Enabled by default. To disable, set PallasTrade::Config.events_log_enabled = false
  #
  # Events are logged at info level. Sensitive parameters are filtered using
  # Rails.application.config.filter_parameters.
  #
  # @example Output
  #   [PallasTrade Event] order.completed | payload: {"id"=>1} | 0.5ms
  #
  class EventLogSubscriber
    NAMESPACE = 'pallastrade'

    class << self
      def attach_to_notifications
        # Always detach first to ensure clean state after code reload.
        # The subscription reference is stored on PallasTrade::Events (in lib/, not
        # reloaded by Zeitwerk) so repeated reloads in development do not leak
        # stale AS::N subscriptions when this class is reloaded.
        detach_from_notifications

        PallasTrade::Events.log_subscription = ActiveSupport::Notifications.subscribe(/\.#{NAMESPACE}$/) do |name, start, finish, _id, payload|
          log_event(name, start, finish, payload)
        end

        Rails.logger.info "[PallasTrade Events] Event logging enabled"
      end

      def detach_from_notifications
        subscription = PallasTrade::Events.log_subscription
        ActiveSupport::Notifications.unsubscribe(subscription) if subscription
        PallasTrade::Events.log_subscription = nil
      end

      def attached?
        !PallasTrade::Events.log_subscription.nil?
      end

      private

      def log_event(name, start, finish, payload)
        pallastrade_event = payload[:event]
        return unless pallastrade_event

        event_name = pallastrade_event.name
        event_payload = filter_sensitive_params(pallastrade_event.payload)
        duration = ((finish - start) * 1000).round(2)

        Rails.logger.info "  \e[36m[PallasTrade Event]\e[0m \e[1m#{event_name}\e[0m | payload: #{event_payload.inspect} | #{duration}ms"
      end

      def filter_sensitive_params(payload)
        parameter_filter.filter(payload)
      end

      def parameter_filter
        @parameter_filter ||= ActiveSupport::ParameterFilter.new(
          Rails.application.config.filter_parameters
        )
      end
    end
  end
end
