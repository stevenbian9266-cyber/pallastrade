# frozen_string_literal: true

module PallasTrade
  module Products
    # Bulk channel publish / unpublish from the admin products list
    # (PRD-20260915-admin-bulk-operations-2, FR-004).
    class BulkChannelAssignment < BulkOperation
      MODES = %w[add remove].freeze

      def initialize(products:, ability:, channels:, mode:)
        super(products: products, ability: ability)
        @channels = channels.to_a
        @mode = mode.to_s
      end

      private

      attr_reader :channels, :mode

      def run(dry_run:)
        warnings = Hash.new(0)

        unless MODES.include?(mode)
          warnings[:invalid_request] += 1
          return result(0, products.size, warnings)
        end

        if channels.empty?
          warnings[:no_channels] += 1
          return result(0, products.size, warnings)
        end

        unless ability.can?(:manage, PallasTrade::ProductPublication)
          warnings[:permission_denied] += 1
          return result(0, products.size, warnings)
        end

        product_ids = products.map(&:id)

        if mode == 'remove'
          pairs = product_ids.size * channels.size
          existing = PallasTrade::ProductPublication
                     .where(product_id: product_ids, channel_id: channels.map(&:id))
                     .count
          warnings[:not_published] += pairs - existing if existing < pairs
        end

        unless dry_run
          channels.each do |channel|
            mode == 'add' ? channel.add_products(product_ids) : channel.remove_products(product_ids)
          end
        end

        result(product_ids.size, 0, warnings)
      end
    end
  end
end
