module PallasTrade
  module Api
    module V3
      # Store API Review serializer — public, approved reviews only.
      class ReviewSerializer < BaseSerializer
        typelize id: :string, product_id: [:string, nullable: true], user_name: [:string, nullable: true],
                 rating: :number, title: [:string, nullable: true], body: [:string, nullable: true],
                 verified_purchase: :boolean, created_at: [:string, nullable: true]

        attribute :id do |review|
          review.prefixed_id
        end

        attribute :product_id do |review|
          review.product&.prefixed_id
        end

        attribute :user_name do |review|
          review.user&.name
        end

        attributes :rating, :title, :body, :verified_purchase, created_at: :iso8601
      end
    end
  end
end
