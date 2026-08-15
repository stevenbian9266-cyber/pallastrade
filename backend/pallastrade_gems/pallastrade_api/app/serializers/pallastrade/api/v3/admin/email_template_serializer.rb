# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        class EmailTemplateSerializer < V3::BaseSerializer
          typelize key: :string, name: :string, subject: :string,
                   body_html: [:string, nullable: true], body_text: [:string, nullable: true],
                   placeholders: [:string, nullable: true], active: :boolean

          attributes :key, :name, :subject, :body_html, :body_text, :placeholders, :active,
                     created_at: :iso8601, updated_at: :iso8601
        end
      end
    end
  end
end
