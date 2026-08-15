# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        # Admin API for the email send log (read-only).
        class EmailLogsController < ResourceController
          scoped_resource :settings

          protected

          def model_class
            PallasTrade::EmailLog
          end

          def serializer_class
            PallasTrade.api.admin_email_log_serializer
          end
        end
      end
    end
  end
end
