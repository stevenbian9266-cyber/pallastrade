# frozen_string_literal: true

module PallasTrade
  module Products
    # Bulk base-price updates from the admin products list
    # (PRD-20260915-admin-bulk-operations-2, FR-001 / FR-002).
    #
    # Only base prices (`price_list_id` nil) are touched, and every write goes
    # through `save!` so the `record_price_history` callback (EU Omnibus) still
    # runs. `preview` and `call` share the same traversal, so the preview
    # counts always match what `call` executes.
    class BulkPriceUpdate < BulkOperation
      MODES = %w[set adjust_percent].freeze

      def initialize(products:, ability:, currency:, mode:, amount: nil, percent: nil)
        super(products: products, ability: ability)
        # Prices are stored uppercased in this codebase (Variant#price_in/set_price
        # both upcase before matching), so normalize once here.
        @currency = currency.to_s.upcase
        @mode = mode.to_s
        @amount = amount
        @percent = percent
      end

      private

      attr_reader :currency, :mode, :amount, :percent

      def run(dry_run:)
        warnings = Hash.new(0)

        unless MODES.include?(mode) && currency.present?
          warnings[:invalid_request] += 1
          return result(0, products.size, warnings)
        end

        target = target_amount(warnings)
        factor = percent_factor(warnings)
        return result(0, products.size, warnings) if target.nil? && factor.nil?

        updated = 0
        skipped = 0

        products.each do |product|
          unless can_manage_prices?(product)
            warnings[:permission_denied] += 1
            skipped += 1
            next
          end

          applied = product.variants_including_master.count do |variant|
            apply_price(variant, target: target, factor: factor, dry_run: dry_run, warnings: warnings)
          end

          if applied.positive?
            updated += 1
          else
            warnings[:no_price] += 1
            skipped += 1
          end
        end

        result(updated, skipped, warnings)
      end

      def target_amount(warnings)
        return nil unless mode == 'set'

        value = parse_decimal(amount)
        if value.nil? || value.negative? || value > PallasTrade::Price::MAXIMUM_AMOUNT
          warnings[:invalid_amount] += 1
          return nil
        end

        value
      end

      def percent_factor(warnings)
        return nil unless mode == 'adjust_percent'

        value = parse_decimal(percent)
        if value.nil?
          warnings[:invalid_percent] += 1
          return nil
        end

        1 + (value / 100)
      end

      def parse_decimal(value)
        return nil if value.blank?

        BigDecimal(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def can_manage_prices?(product)
        return true if product.new_record?

        ability.can?(:manage, PallasTrade::Price.new(variant_id: product.default_variant.id))
      end

      # @return [Boolean] true when the variant price was created/updated (or
      #   would be, in preview mode)
      def apply_price(variant, target:, factor:, dry_run:, warnings:)
        price = variant.prices.base_prices.find_by(currency: currency)

        if mode == 'set'
          if price.nil?
            return true if dry_run

            variant.prices.create!(currency: currency, amount: target)
            return true
          end
          return true if price.amount == target

          price.amount = target
        else
          return false if price.nil? || price.amount.nil?

          new_amount = (price.amount * factor).round(2)
          if new_amount.negative?
            warnings[:negative_result] += 1
            return false
          end
          if new_amount > PallasTrade::Price::MAXIMUM_AMOUNT
            warnings[:above_maximum] += 1
            return false
          end
          return true if new_amount == price.amount

          price.amount = new_amount
        end

        price.save! unless dry_run
        true
      end
    end
  end
end
