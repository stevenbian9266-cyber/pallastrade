# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        class RedirectSerializer < V3::BaseSerializer
          typelize from_path: :string, to_path: :string, status_code: :integer, active: :boolean,
                   title: [:string, nullable: true], description: [:string, nullable: true]

          attributes :from_path, :to_path, :status_code, :active, :title, :description, created_at: :iso8601, updated_at: :iso8601
        end
      end
    end
  end
end
