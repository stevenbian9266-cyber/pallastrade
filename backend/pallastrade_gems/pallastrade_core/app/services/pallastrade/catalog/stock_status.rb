# frozen_string_literal: true

module PallasTrade
  module Catalog
    # Catalog F-2 (PRD-20260916-catalog-batch-f2-stock-shipping): turns precise
    # stock into a *bucket* the storefront may show to shoppers.
    #
    #   > threshold        → in_stock
    #   1..threshold       → low_stock   ("Only a few left")
    #   0 + preorderable   → preorder
    #   0 + backorderable  → backorder
    #   otherwise          → out_of_stock
    #
    # Two rules make this the single source of truth:
    #
    # * Availability is read through {PallasTrade::Stock::Quantifier}, the same
    #   object `Variant#in_stock?` / `#purchasable?` use, so the bucket can never
    #   disagree with the booleans the API already exposes.
    # * When the variant does not track inventory (`should_track_inventory?`),
    #   supply is unlimited → `in_stock`. Never invent scarcity.
    #
    # Exact quantities never leave this class — callers only get an enum.
    class StockStatus
      IN_STOCK = 'in_stock'
      LOW_STOCK = 'low_stock'
      PREORDER = 'preorder'
      BACKORDER = 'backorder'
      OUT_OF_STOCK = 'out_of_stock'

      # Best → worst. A product reports the best bucket any of its variants is
      # in, mirroring `PallasTrade::Stock::Availability` semantics.
      VALUES = [IN_STOCK, LOW_STOCK, PREORDER, BACKORDER, OUT_OF_STOCK].freeze

      RANK = VALUES.each_with_index.to_h.freeze

      DEFAULT_THRESHOLD = 5

      class << self
        # @param threshold [Integer, nil] store preference; invalid → default
        # @return [Integer] a positive threshold
        def normalize_threshold(threshold)
          value = threshold.to_i
          value.positive? ? value : DEFAULT_THRESHOLD
        end

        # @param store [PallasTrade::Store, nil] store the threshold comes from
        def threshold_for(store)
          normalize_threshold(store&.preferred_low_stock_threshold)
        end

        # Bucket for one variant. Reads preloaded `stock_items` /
        # `active_stock_reservations` when present, so batch callers pay no
        # per-variant query.
        #
        # @return [String] one of {VALUES}
        def for_variant(variant, threshold:)
          return IN_STOCK if variant.nil? || !variant.should_track_inventory?

          available = PallasTrade::Stock::Quantifier.new(variant).total_on_hand
          return IN_STOCK if available.nil? || available == BigDecimal::INFINITY

          available = available.to_i
          return IN_STOCK if available > threshold
          return LOW_STOCK if available.positive?
          return PREORDER if variant.preorder?

          variant.backorderable? ? BACKORDER : OUT_OF_STOCK
        end

        # Bucket for a product = best bucket among its variants. Associations
        # are expected to be preloaded by the caller (`variants` →
        # `stock_items` → `active_stock_reservations`).
        def for_product(product, threshold:)
          return OUT_OF_STOCK if product.nil?

          variants = product.association(:variants).loaded? ? product.variants : product.variants.to_a
          return for_variant(product.default_variant, threshold: threshold) if variants.empty?

          variants.map { |variant| for_variant(variant, threshold: threshold) }.
            min_by { |status| RANK.fetch(status, RANK.size) }
        end

        # Batch helper: `{ product_id => bucket }` for a page of products, using
        # the associations the caller already preloaded.
        #
        # @return [Hash{Integer => String}]
        def map_for_products(products, threshold:)
          Array(products).each_with_object({}) do |product, acc|
            acc[product.id] = for_product(product, threshold: threshold)
          end
        end
      end
    end
  end
end
