# frozen_string_literal: true

module PallasTrade
  # Detects products whose URL (slug) changed at some point and reports the old
  # vs current slugs so the admin can create SEO 301 redirects for the old URLs.
  #
  # Data source: friendly_id `:history` — every slug a product ever had is
  # recorded in `friendly_id_slugs` (sluggable_type = PallasTrade::Product).
  # No new table/migration is required.
  #
  # @return [Array<Hash>] each entry:
  #   { product:, locale:, old_slug:, current_slug:, from_path:, to_path:, handled: }
  #   - handled: true when a redirect with from_path `/products/{old_slug}` already exists
  class ProductUrlChange
    # @param store [PallasTrade::Store]
    # @return [Array<Hash>]
    def self.call(store)
      new(store).call
    end

    def initialize(store)
      @store = store
    end

    def call
      products = @store.products.includes(:translations)
      return [] if products.empty?

      product_ids = products.map(&:id)

      # All slug-history rows for this store's products (current + old slugs).
      rows = FriendlyId::Slug
             .where(sluggable_type: PallasTrade::Product.name, sluggable_id: product_ids, deleted_at: nil)
             .order(:id)
             .pluck(:sluggable_id, :locale, :slug)

      existing_from_paths = @store.redirects.active.pluck(:from_path).to_set
      rows_by_product = rows.group_by(&:first)

      result = []
      products.each do |product|
        product_rows = rows_by_product[product.id] || []
        next if product_rows.empty?

        current_slug_by_locale = {}
        product.translations.each do |translation|
          current_slug_by_locale[translation.locale.to_s] = translation.slug if translation.slug.present?
        end
        current_slug_by_locale[I18n.locale.to_s] ||= product.slug if product.slug.present?

        seen = {}
        product_rows.each do |_product_id, locale, old_slug|
          next if old_slug.blank?
          next if old_slug.start_with?('deleted-')

          current_slug = current_slug_by_locale[locale]
          next if current_slug.blank? || old_slug == current_slug
          next if seen[[locale, old_slug]]

          seen[[locale, old_slug]] = true
          from_path = "/products/#{old_slug}"
          result << {
            product: product,
            locale: locale,
            old_slug: old_slug,
            current_slug: current_slug,
            from_path: from_path,
            to_path: "/products/#{current_slug}",
            handled: existing_from_paths.include?(from_path),
          }
        end
      end
      result
    end
  end
end
