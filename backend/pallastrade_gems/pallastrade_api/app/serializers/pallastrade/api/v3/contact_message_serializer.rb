module PallasTrade
  module Api
    module V3
      class ContactMessageSerializer < BaseSerializer
        # R1 (2026-09-04): typelize must not declare the custom :iso8601 scalar —
        # Typelizer would emit a raw `iso8601` TS type. Timestamps type as string
        # in typelize; the Alba attribute macro below keeps :iso8601 formatting.
        typelize kind: :string, name: [:string, nullable: true],
                 email: :string, subject: [:string, nullable: true],
                 body: :string, status: :string, created_at: :string

        attributes :kind, :name, :email, :subject, :body, :status, created_at: :iso8601
      end
    end
  end
end
