module PallasTrade
  module V2
    module Storefront
      class PostCategorySerializer < ::PallasTrade::Api::V2::BaseSerializer
        include PallasTrade::Api::V2::PublicMetafieldsConcern

        set_type :post_category

        attributes :title, :slug, :created_at, :updated_at

        attribute :description do |category|
          category.description.to_plain_text if category.description.present?
        end

        has_many :posts, serializer: PallasTrade.api.storefront_post_serializer, record_type: :post, if: proc { |_record, params|
          params[:include_posts] == true
        } do |category|
          category.posts.published.by_newest
        end
      end
    end
  end
end
