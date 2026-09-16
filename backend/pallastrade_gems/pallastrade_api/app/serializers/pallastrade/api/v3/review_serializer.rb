module PallasTrade
  module Api
    module V3
      # Store API Review serializer — public, approved reviews only.
      class ReviewSerializer < BaseSerializer
        typelize id: :string, product_id: [:string, nullable: true], user_name: [:string, nullable: true],
                 rating: :number, title: [:string, nullable: true], body: [:string, nullable: true],
                 verified_purchase: :boolean, created_at: [:string, nullable: true],
                 image_urls: [:string, multi: true]

        attribute :id do |review|
          review.prefixed_id
        end

        attribute :product_id do |review|
          review.product&.prefixed_id
        end

        attribute :user_name do |review|
          review.user&.name
        end

        # Review photos (F-1). Flat URL array on purpose: an inline array of
        # objects collapses to `type: object` in the generated OpenAPI schema.
        # Only approved reviews reach this serializer, so pending photos never
        # leak a URL.
        #
        # `image_url_for` is not used here: it expects an `Attached::One` proxy
        # (or a record responding to `attached?`), while `has_many_attached`
        # yields attachment records — the same route helper is called directly.
        attribute :image_urls do |review|
          next [] unless review.images.attached?

          review.ordered_images.filter_map do |attachment|
            Rails.application.routes.url_helpers.cdn_image_url(attachment)
          end
        end

        attributes :rating, :title, :body, :verified_purchase, created_at: :iso8601
      end
    end
  end
end
