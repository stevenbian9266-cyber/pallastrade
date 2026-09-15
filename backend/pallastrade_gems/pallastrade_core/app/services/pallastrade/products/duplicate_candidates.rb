# frozen_string_literal: true

module PallasTrade
  module Products
    # Duplicate Detection V1 (PRD-20260915-catalog-batch-d2-duplicate-detection):
    # the single source of truth for the duplicate signals the merchant worklist
    # shows.
    #
    #   duplicate_barcode — variants of this store sharing a barcode
    #   duplicate_sku     — variants of this store sharing a SKU (case-insensitive)
    #   duplicate_name    — products of this store sharing a normalized name
    #
    # Read-only by design: nothing here merges, renames or archives anything.
    # Merging two products has to reconcile variants, reviews, redirects and
    # historical transactions, so it stays a separate project (D-3).
    class DuplicateCandidates
      SIGNALS = %w[duplicate_barcode duplicate_sku duplicate_name].freeze
      PRODUCTS_PER_GROUP = 5
      MAX_GROUPS = 500

      # @!attribute [r] signal
      #   @return [String] one of {SIGNALS}
      # @!attribute [r] key
      #   @return [String] the shared value (barcode, SKU or normalized name)
      # @!attribute [r] products
      #   @return [Array<PallasTrade::Product>] at most PRODUCTS_PER_GROUP of them
      # @!attribute [r] total_count
      #   @return [Integer] how many products carry that value
      Group = Struct.new(:signal, :key, :products, :total_count, keyword_init: true) do
        # @return [Integer] products the list does not show (0 when everything fits)
        def hidden_count
          [total_count - products.size, 0].max
        end
      end

      def self.call(store, signal: nil, max_groups: MAX_GROUPS)
        new(store: store, signal: signal, max_groups: max_groups).call
      end

      def self.counts(store)
        new(store: store).counts
      end

      def self.valid_signal?(signal)
        SIGNALS.include?(signal.to_s)
      end

      def initialize(store:, signal: nil, max_groups: MAX_GROUPS)
        @store = store
        @signal = self.class.valid_signal?(signal) ? signal.to_s : nil
        @max_groups = max_groups
      end

      attr_reader :store, :signal, :max_groups

      # @return [Array<Group>] candidate groups, biggest first, capped at max_groups
      def call
        @call ||= all_groups.first(max_groups)
      end

      # Group count per signal, derived from the very same groups the list shows,
      # so a count can never disagree with the rows underneath it.
      # @return [Hash{String => Integer}]
      def counts
        @counts ||= SIGNALS.index_with { |key| call.count { |group| group.signal == key } }
      end

      private

      def all_groups
        @all_groups ||= SIGNALS.flat_map { |key| groups_for(key) }
                               .sort_by { |group| [-group.total_count, group.key.to_s] }
      end

      def groups_for(key)
        return [] unless signal.nil? || signal == key

        case key
        when 'duplicate_barcode' then variant_groups(key, :barcode)
        when 'duplicate_sku' then variant_groups(key, :sku)
        else name_groups(key)
        end
      end

      # --- signals ---------------------------------------------------------

      def variant_groups(key, column)
        scope = variant_scope
        expression = normalized_expression(PallasTrade::Variant.arel_table[column])
        candidates = scope.where(expression.in(duplicated_keys(scope, expression)))
                          .includes(:product)
                          .to_a

        # (normalized value, product) pairs: a product can appear several times when
        # two of its own variants collide, and build_group collapses that back to one.
        pairs = candidates.map { |variant| [normalize(variant.public_send(column)), variant.product] }
        groups_from(key, pairs)
      end

      def name_groups(key)
        scope = product_scope
        expression = normalized_expression(PallasTrade::Product.arel_table[:name])
        candidates = scope.where(expression.in(duplicated_keys(scope, expression))).to_a

        # `read_attribute` keeps the Ruby key aligned with the SQL column the
        # grouping ran on (Mobility may otherwise resolve `name` from a
        # translation row and produce a key that never matched).
        pairs = candidates.map { |product| [normalize(product.read_attribute(:name)), product] }
        groups_from(key, pairs)
      end

      # @return [Array<String>] non-blank values carried by more than one product.
      #
      # Blank values are dropped *here* rather than with a `where.not(col: [nil, ''])`
      # scope: that form renders `col = NULL OR col IS NULL` inside NOT(), which is
      # NULL (therefore never true) for every real row, and on a Mobility-translated
      # attribute the value is cast in surprising ways. Grouping first and filtering
      # the keys keeps the semantics obvious.
      def duplicated_keys(scope, expression)
        scope.group(expression)
             .having(PallasTrade::Product.arel_table[:id].count(true).gt(1))
             .count
             .keys
             .reject(&:blank?)
      end

      def groups_from(key, pairs)
        pairs.group_by(&:first)
             .filter_map { |group_key, entries| build_group(key, group_key, entries.map(&:last)) }
      end

      # A single product may bring several variants to the same group (two of its
      # own SKUs colliding) — the group counts products, not rows.
      def build_group(key, group_key, products)
        unique = products.uniq(&:id)
        return nil if group_key.blank? || unique.size < 2

        Group.new(signal: key, key: group_key, products: unique.first(PRODUCTS_PER_GROUP),
                  total_count: unique.size)
      end

      # --- scopes ----------------------------------------------------------

      def product_scope
        PallasTrade::Product.where(store_id: store.id)
                            .where(deleted_at: nil)
                            .where.not(status: 'archived')
      end

      # Variants carry no store of their own — the store comes from the product,
      # and the join keeps another store's SKU/barcode out of a group.
      def variant_scope
        PallasTrade::Variant.where(deleted_at: nil)
                            .joins(:product)
                            .merge(product_scope)
      end

      # --- helpers ---------------------------------------------------------

      def normalize(value)
        value.to_s.strip.downcase
      end

      # `LOWER(TRIM(column))` as an Arel node: this class never assembles SQL by
      # string interpolation, so nothing here can drift into an injection finding.
      def normalized_expression(attribute)
        Arel::Nodes::NamedFunction.new('LOWER', [Arel::Nodes::NamedFunction.new('TRIM', [attribute])])
      end
    end
  end
end
