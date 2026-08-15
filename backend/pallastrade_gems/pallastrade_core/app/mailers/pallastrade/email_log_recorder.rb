# frozen_string_literal: true

module PallasTrade
  # ActionMailer observer that records every outgoing mail as an EmailLog row
  # (per store), so admins can audit sends from the Email → Send log page.
  # Registered in pallastrade_core engine initialization. Only records for
  # PallasTrade mailers where a store can be resolved.
  #
  # ActionMailer observers must expose `delivered_email` / `failed_email` as
  # CLASS methods (Rails calls `observer.delivered_email(message)`).
  class EmailLogRecorder
    class << self
      def delivered_email(message)
        record(message, 'sent')
      rescue StandardError => e
        Rails.logger.warn("[pallastrade_email_log] failed to record delivered email: #{e.message}")
      end

      def failed_email(message)
        record(message, 'failed')
      rescue StandardError => e
        Rails.logger.warn("[pallastrade_email_log] failed to record failed email: #{e.message}")
      end

      private

      def record(message, status)
        store = message.instance_variable_get(:@_pallastrade_store)
        return if store.nil?

        mailer_class = message.instance_variable_get(:@_pallastrade_mailer)
        mailer = mailer_class.to_s.demodulize.sub(/Mailer\z/, '').underscore
        action = message.instance_variable_get(:@_pallastrade_action).to_s

        PallasTrade::EmailLog.create!(
          store: store,
          mailer: mailer,
          action: action,
          to: Array(message.to).join(', '),
          from: Array(message.from).join(', '),
          subject: message.subject.to_s,
          status: status,
          error: status == 'failed' ? message.error&.message : nil,
          sent_at: Time.current
        )
      end

      def resolve_store(message)
        message.instance_variable_get(:@_pallastrade_store)
      end
    end
  end
end
