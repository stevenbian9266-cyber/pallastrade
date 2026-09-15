# frozen_string_literal: true

module PallasTrade
  module ProductHistory
    # Reads the product timeline for the admin product page
    # (PRD-20260915-catalog-batch-d1-product-history).
    #
    # Two sources are merged, newest first:
    # - audit entries written by `ProductHistory::Recorder` (product create/update,
    #   bulk price/inventory/channel/status operations), and
    # - `PriceHistory` rows, which already record every base-price change per SKU
    #   (so inline price edits on the product form show up without extra writes).
    class Timeline
      DEFAULT_LIMIT = 20
      RESOURCE_TYPE = 'PallasTrade::Product'

      # @!attribute [r] kind
      #   @return [String] 'created' / 'updated' / 'price' / 'bulk_price_updated'…
      # @!attribute [r] occurred_at
      #   @return [Time, nil]
      # @!attribute [r] actor_label
      #   @return [String, nil]
      # @!attribute [r] changes
      #   @return [Array<Hash>] [{ field:, before:, after: }]
      # @!attribute [r] metadata
      #   @return [Hash]
      Entry = Struct.new(:kind, :occurred_at, :actor_label, :changes, :metadata, keyword_init: true)

      def self.call(product:, limit: DEFAULT_LIMIT)
        new(product: product, limit: limit).call
      end

      def initialize(product:, limit: DEFAULT_LIMIT)
        @product = product
        @limit = limit
      end

      attr_reader :product, :limit

      # @return [Array<Entry>] newest first, capped at `limit`
      def call
        (audit_entries + price_entries).sort_by { |entry| entry.occurred_at || Time.at(0) }.reverse.first(limit)
      end

      private

      def audit_entries
        PallasTrade::AuditLog
          .for_resource(RESOURCE_TYPE, product.id)
          .order(occurred_at: :desc)
          .limit(limit)
          .map { |log| entry_from_audit(log) }
      end

      def entry_from_audit(log)
        Entry.new(
          kind: log.action.to_s.delete_prefix('product.'),
          occurred_at: log.occurred_at,
          actor_label: log.actor_label,
          changes: changes_from(log),
          metadata: log.metadata || {}
        )
      end

      def changes_from(log)
        before = log.before || {}
        after = log.after || {}

        (before.keys | after.keys).map do |field|
          { field: field, before: before[field], after: after[field] }
        end
      end

      # Price rows only carry the new amount, so the "was" value comes from the
      # previous row of the same price record (loaded in the same window).
      def price_entries
        rows = PallasTrade::PriceHistory
               .where(variant_id: variant_ids)
               .order(recorded_at: :desc, id: :desc)
               .includes(:variant)
               .limit(limit * 3)

        rows.each_with_index.map do |row, index|
          previous = rows[(index + 1)..].find { |candidate| candidate.price_id == row.price_id }
          entry_from_price(row, previous)
        end.first(limit)
      end

      def entry_from_price(row, previous)
        Entry.new(
          kind: 'price',
          occurred_at: row.recorded_at,
          actor_label: nil,
          changes: [
            { field: 'price', before: previous&.amount, after: row.amount },
            { field: 'currency', before: nil, after: row.currency }
          ],
          metadata: { 'variant_sku' => row.variant&.sku, 'variant_id' => row.variant&.prefixed_id }
        )
      end

      def variant_ids
        product.variants_including_master.select(:id)
      end
    end
  end
end
