# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        class ContactMessageSerializer < V3::BaseSerializer
          typelize kind: :string, name: [:string, nullable: true], email: :string,
                   subject: [:string, nullable: true], body: :string, status: :string

          attributes :kind, :name, :email, :subject, :body, :status,
                     created_at: :iso8601, updated_at: :iso8601
        end
      end
    end
  end
end
