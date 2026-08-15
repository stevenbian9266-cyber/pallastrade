# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        # Admin API for inbox & feedback (contact messages).
        class ContactMessagesController < ResourceController
          scoped_resource :settings

          protected

          def model_class
            PallasTrade::ContactMessage
          end

          def serializer_class
            PallasTrade.api.admin_contact_message_serializer
          end

          def permitted_params
            params.permit(:kind, :status, :name, :email, :subject, :body)
          end
        end
      end
    end
  end
end
