# frozen_string_literal: true

module PallasTrade
  module Products
    # Bulk inventory adjustments at one stock location from the admin products
    # list (PRD-20260915-admin-bulk-operations-2, FR-003).
    #
    # Products that do not track inventory are skipped (with a warning) instead
    # of silently creating useless stock items. `preview` performs the same
    # traversal without writing.
    class BulkInventoryAdjust < BulkOperation
      def initialize(products:, ability:, stock_location:, delta:)
        super(products: products, ability: ability)
        @stock_location = stock_location
        @delta = delta.to_i
      end

      private

      attr_reader :stock_location, :delta

      def run(dry_run:)
        warnings = Hash.new(0)

        if stock_location.nil?
          warnings[:stock_location_missing] += 1
          return result(0, products.size, warnings)
        end

        if delta.zero?
          warnings[:zero_delta] += 1
          return result(0, products.size, warnings)
        end

        updated = 0
        skipped = 0

        products.each do |product|
          unless can_manage_stock_items?(product)
            warnings[:permission_denied] += 1
            skipped += 1
            next
          end

          tracked = product.variants_including_master.select(&:track_inventory?)
          if tracked.empty?
            warnings[:inventory_not_tracked] += 1
            skipped += 1
            next
          end

          tracked.each do |variant|
            item = PallasTrade::StockItem.find_or_initialize_by(
              variant_id: variant.id,
              stock_location_id: stock_location.id
            )
            new_count = item.count_on_hand.to_i + delta
            if new_count.negative?
              new_count = 0
              warnings[:clamped_at_zero] += 1
            end

            next if dry_run || new_count == item.count_on_hand.to_i

            item.set_count_on_hand(new_count)
          end

          updated += 1
        end

        result(updated, skipped, warnings)
      end

      def can_manage_stock_items?(product)
        return true if product.new_record?

        ability.can?(:manage, PallasTrade::StockItem.new(variant_id: product.default_variant.id))
      end
    end
  end
end
