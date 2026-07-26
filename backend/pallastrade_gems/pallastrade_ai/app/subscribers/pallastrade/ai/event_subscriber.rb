# frozen_string_literal: true

module PallasTrade
  module AI
    # Lifecycle event subscriber for AI operations.
    # Follows the PallasTrade::Subscriber pattern.
    class EventSubscriber < PallasTrade::Subscriber
      subscribes_to(
        'ai.provider.created',
        'ai.provider.updated',
        'ai.provider.credential_rotated',
        'ai.provider.connection_tested',
        'ai.model.created',
        'ai.model.updated',
        'ai.capability_setting.updated',
        'ai.run.queued',
        'ai.run.started',
        'ai.run.succeeded',
        'ai.run.failed',
        'ai.run.skipped',
        'ai.run.cancelled',
        async: false
      )

      on 'ai.provider.created', :log_event
      on 'ai.provider.updated', :log_event
      on 'ai.provider.credential_rotated', :log_event
      on 'ai.provider.connection_tested', :log_event
      on 'ai.model.created', :log_event
      on 'ai.model.updated', :log_event
      on 'ai.capability_setting.updated', :log_event
      on 'ai.run.queued', :log_event
      on 'ai.run.started', :log_event
      on 'ai.run.succeeded', :log_event
      on 'ai.run.failed', :log_event
      on 'ai.run.skipped', :log_event
      on 'ai.run.cancelled', :log_event

      def log_event(event)
        Rails.logger.debug("[PallasTrade AI] Event: #{event.name} payload: #{event.payload.keys}")
      end
    end
  end
end
