# frozen_string_literal: true

module PallasTrade
  module CatalogHealth
    # Single source of truth for the seven Catalog Health issues
    # (PRD-20260915-admin-catalog-health-v1 §3.1).
    #
    # Both the worklist page (`PallasTrade::Admin::CatalogHealthController`) and
    # the products-list drill-down resolve their numbers through this module, so
    # a count always equals the length of the list it links to.
    class Issues
      KEYS = %w[
        missing_media
        missing_description
        missing_seo
        missing_translations
        active_zero_stock
        redirect_unresolved
        old_drafts
      ].freeze

      # Issues whose drill-down is the filtered products list. The remaining two
      # link to the page that already owns their remediation flow
      # (Product Translations coverage / Redirects URL changes).
      PRODUCT_FILTER_KEYS = %w[
        missing_media
        missing_description
        missing_seo
        active_zero_stock
        old_drafts
      ].freeze

      # Drafts untouched for longer than this are surfaced as `old_drafts`.
      OLD_DRAFT_DAYS = 30

      # Only these translatable fields may be interpolated into SQL below.
      TRANSLATED_FIELDS = %w[description meta_title meta_description].freeze

      class << self
        # @param key [String, Symbol]
        # @return [Boolean] true for a known issue key
        def valid?(key)
          KEYS.include?(key.to_s)
        end

        # @param key [String, Symbol]
        # @return [Boolean] true when the key filters the products list
        def valid_filter?(key)
          PRODUCT_FILTER_KEYS.include?(key.to_s)
        end

        # @param base_scope [ActiveRecord::Relation] products already scoped to
        #   the current store + ability
        # @return [ActiveRecord::Relation, nil] nil when the key is not a
        #   products-list filter
        def product_relation(base_scope, key, store:)
          scope = base_scope.not_archived

          case key.to_s
          when 'missing_media' then missing_media(scope)
          when 'missing_description' then blank_translation(scope, 'description', locale: default_locale(store))
          when 'missing_seo' then missing_seo(scope, locale: default_locale(store))
          when 'active_zero_stock' then active_zero_stock(scope)
          when 'old_drafts' then old_drafts(scope)
          end
        end

        # @return [Integer] issue count for one store (0 for unknown keys)
        def count(store, key)
          case key.to_s
          when *PRODUCT_FILTER_KEYS
            product_relation(store.products, key, store: store)&.count.to_i
          when 'missing_translations' then missing_translations_count(store)
          when 'redirect_unresolved' then redirect_unresolved_count(store)
          else 0
          end
        end

        # Number of (product × locale) pairs still missing a `name` translation
        # in a non-default supported locale. Same rule as the Product
        # Translations coverage page (`where.not(name: [nil, ''])`), so the
        # worklist number and that page stay consistent.
        # @return [Integer]
        def missing_translations_count(store)
          locales = other_locales(store)
          return 0 if locales.empty?

          product_ids = store.product_ids
          return 0 if product_ids.empty?

          translated = PallasTrade::Product::Translation
                       .where(pallastrade_product_id: product_ids, locale: locales)
                       .where.not(name: [nil, ''])
                       .count

          (product_ids.size * locales.size) - translated
        end

        # URL changes that never received a 301 — the same number the Redirects
        # page shows in its "URL changes" section (`handled: false`).
        # @return [Integer]
        def redirect_unresolved_count(store)
          PallasTrade::ProductUrlChange.call(store).count { |change| change[:handled] == false }
        end

        private

        def default_locale(store)
          (store.default_locale.presence || I18n.default_locale).to_s
        end

        def other_locales(store)
          (store.supported_locales_list.map(&:to_s) - [default_locale(store)]).sort
        end

        def product_table
          PallasTrade::Product.table_name
        end

        def product_arel
          PallasTrade::Product.arel_table
        end

        # 原始 SQL 一律经 `sanitize_sql_array` 组装（参数化入口）。
        # 动态部分仅允许：常量表名、白名单列名（`TRANSLATED_FIELDS`）、绑参值。
        def raw_sql(fragment, *binds)
          ActiveRecord::Base.sanitize_sql_array([fragment, *binds])
        end

        # Products (and all their variants, master included) without a single
        # asset. Reads `pallastrade_assets` instead of the `media_count`
        # counters because `PallasTrade::Asset` does not declare a counter
        # cache — the rows are the truth.
        def missing_media(scope)
          scope.where(raw_sql(<<~SQL.squish))
            NOT EXISTS (
              SELECT 1
              FROM #{PallasTrade::Asset.table_name} assets
              LEFT JOIN #{PallasTrade::Variant.table_name} variants
                ON assets.viewable_type = 'PallasTrade::Variant'
               AND variants.id = assets.viewable_id
              WHERE (assets.viewable_type = 'PallasTrade::Product' AND assets.viewable_id = #{product_table}.id)
                 OR (variants.product_id = #{product_table}.id AND variants.deleted_at IS NULL)
            )
          SQL
        end

        # Effective value for one locale: the translation row wins, otherwise
        # Mobility's `column_fallback` falls back to the model column.
        def blank_translation(scope, field, locale:)
          raise ArgumentError, "unsupported field #{field}" unless TRANSLATED_FIELDS.include?(field)

          translation_join(scope, locale).where(
            raw_sql("COALESCE(NULLIF(catalog_health_translations.#{field}, ''), NULLIF(#{product_table}.#{field}, '')) IS NULL")
          )
        end

        def missing_seo(scope, locale:)
          translation_join(scope, locale).where(raw_sql(<<~SQL.squish))
            COALESCE(NULLIF(catalog_health_translations.meta_title, ''), NULLIF(#{product_table}.meta_title, '')) IS NULL
            OR COALESCE(NULLIF(catalog_health_translations.meta_description, ''), NULLIF(#{product_table}.meta_description, '')) IS NULL
          SQL
        end

        def translation_join(scope, locale)
          translations = PallasTrade::Product::Translation.table_name

          scope.joins(raw_sql(<<~SQL.squish, locale))
            LEFT OUTER JOIN #{translations} catalog_health_translations
              ON catalog_health_translations.pallastrade_product_id = #{product_table}.id
             AND catalog_health_translations.locale = ?
             AND catalog_health_translations.deleted_at IS NULL
          SQL
        end

        # Active products where nothing can be bought: no variant is untracked,
        # preorderable, in stock or backorderable. Pre-order/backorder SKUs stay
        # out of the report because they are still purchasable.
        def active_zero_stock(scope)
          scope.where(status: 'active').where(raw_sql(<<~SQL.squish))
            NOT EXISTS (
              SELECT 1
              FROM #{PallasTrade::Variant.table_name} variants
              WHERE variants.product_id = #{product_table}.id
                AND variants.deleted_at IS NULL
                AND (
                  variants.track_inventory = false
                  OR variants.preorderable = true
                  OR EXISTS (
                    SELECT 1
                    FROM #{PallasTrade::StockItem.table_name} stock_items
                    WHERE stock_items.variant_id = variants.id
                      AND stock_items.deleted_at IS NULL
                      AND (stock_items.count_on_hand > 0 OR stock_items.backorderable = true)
                  )
                )
            )
          SQL
        end

        def old_drafts(scope)
          scope.where(status: 'draft').where(product_arel[:updated_at].lt(OLD_DRAFT_DAYS.days.ago))
        end
      end
    end
  end
end
