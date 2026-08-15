# frozen_string_literal: true

module PallasTrade
  module Admin
    # Read-only send log (Email → Send log). Records written by
    # PallasTrade::EmailLogRecorder whenever a mail is delivered/fails.
    class EmailLogsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern

      private

      def model_class
        PallasTrade::EmailLog
      end

      def scope
        current_store.email_logs.recent
      end

      def object_name
        'email_log'
      end
    end
  end
end
