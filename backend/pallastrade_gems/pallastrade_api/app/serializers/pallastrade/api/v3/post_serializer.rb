# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      class PostSerializer < BaseSerializer
        typelize title: :string, slug: :string, excerpt: [:string, nullable: true],
                 author: [:string, nullable: true], published_at: [:string, nullable: true],
                 cover_image_url: [:string, nullable: true],
                 body: [:string, nullable: true], body_html: [:string, nullable: true],
                 seo_title: [:string, nullable: true], seo_description: [:string, nullable: true]

        attributes :title, :slug, :excerpt, :author, :seo_title, :seo_description,
                   published_at: :iso8601

        attribute :cover_image_url do |post|
          image_url_for(post.cover_image)
        end

        attribute :body do |post|
          post.body&.to_plain_text
        end

        attribute :body_html do |post|
          post.body&.body&.to_s.to_s
        end
      end
    end
  end
end
