# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        # Admin API for editable email templates.
        class EmailTemplatesController < ResourceController
          scoped_resource :settings

          protected

          def model_class
            PallasTrade::EmailTemplate
          end

          def serializer_class
            PallasTrade.api.admin_email_template_serializer
          end

          def permitted_params
            params.permit(:key, :name, :subject, :body_html, :body_text, :placeholders, :active)
          end
        end
      end
    end
  end
end
