module PallasTrade
  module Api
    module V3
      class ContactMessageSerializer < BaseSerializer
        typelize kind: :string, name: [:string, nullable: true],
                 email: :string, subject: [:string, nullable: true],
                 body: :string, status: :string, created_at: :iso8601

        attributes :kind, :name, :email, :subject, :body, :status, created_at: :iso8601
      end
    end
  end
end
