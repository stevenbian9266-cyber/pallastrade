# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        class EmailLogSerializer < V3::BaseSerializer
          typelize mailer: :string, action: :string, to: :string,
                   from: [:string, nullable: true], subject: [:string, nullable: true],
                   status: :string, error: [:string, nullable: true]

          attributes :mailer, :action, :to, :from, :subject, :status, :error,
                     sent_at: :iso8601, created_at: :iso8601
        end
      end
    end
  end
end
