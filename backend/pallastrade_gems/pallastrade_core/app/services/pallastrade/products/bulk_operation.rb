# frozen_string_literal: true

module PallasTrade
  module Products
    # Shared plumbing for the admin bulk operations
    # (PRD-20260915-admin-bulk-operations-2).
    #
    # `preview` and `call` go through the same `run(dry_run:)` traversal, so the
    # previewed counts always match what `call` executes; every record that
    # refuses the operation is collected in `warnings` instead of aborting the
    # batch.
    class BulkOperation
      Result = Struct.new(:selected_count, :updated_count, :skipped_count, :warnings, keyword_init: true)

      def initialize(products:, ability:)
        @products = products
        @ability = ability
      end

      def preview
        run(dry_run: true)
      end

      def call
        run(dry_run: false)
      end

      private

      attr_reader :products, :ability

      def result(updated, skipped, warnings)
        Result.new(
          selected_count: products.size,
          updated_count: updated,
          skipped_count: skipped,
          warnings: warnings
        )
      end
    end
  end
end
