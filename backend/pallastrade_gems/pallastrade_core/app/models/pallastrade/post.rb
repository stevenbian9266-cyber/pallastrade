# frozen_string_literal: true

# PallasTrade CMS blog post. Stores a single article scoped to a store, with
# multi-language title/excerpt/body (ActionText) and optional SEO metadata.
# `published_at` nil = draft; a future value = scheduled publish.
module PallasTrade
  class Post < PallasTrade.base_class
    has_prefix_id :post

    extend FriendlyId
    include PallasTrade::TranslatableResource
    include PallasTrade::SingleStoreResource

    UNIQUENESS_SCOPE = %i[store_id].freeze

    #
    # FriendlyId
    #
    friendly_id :slug_candidates, use: %i[slugged scoped history], scope: UNIQUENESS_SCOPE

    #
    # Associations
    #
    belongs_to :store, class_name: 'PallasTrade::Store', inverse_of: :posts

    #
    # Translations
    #
    TRANSLATABLE_FIELDS = %i[title excerpt seo_title seo_description].freeze
    RICH_TEXT_TRANSLATABLE_FIELDS = %i[body].freeze
    translates(*TRANSLATABLE_FIELDS, column_fallback: PallasTrade.mobility_column_fallback)

    #
    # ActionText (rich body, per locale)
    #
    translates :body, backend: :action_text

    #
    # ActiveStorage
    #
    has_one_attached :cover_image

    #
    # Validations
    #
    validates :title, presence: true
    validates :slug, presence: true, uniqueness: { scope: UNIQUENESS_SCOPE }

    #
    #  Ransack
    #
    self.whitelisted_ransackable_attributes = %w[title slug author published_at]

    #
    # Scopes
    #
    scope :published, -> { where(arel_table[:published_at].lteq(Time.current)) }
    scope :drafts, -> { where(published_at: nil) }
    scope :scheduled, -> { where(arel_table[:published_at].gt(Time.current)) }
    scope :newest_first, -> { order(Arel.sql('published_at DESC NULLS LAST')) }

    # @return [Boolean] true when the post is currently visible to storefront
    def published?
      published_at.present? && published_at <= Time.current
    end

    def scheduled?
      published_at.present? && published_at > Time.current
    end

    private

    def slug_candidates
      [:title, [:title, :id]]
    end
  end
end
