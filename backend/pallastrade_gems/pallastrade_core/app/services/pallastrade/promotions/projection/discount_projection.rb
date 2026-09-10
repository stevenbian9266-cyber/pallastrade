# frozen_string_literal: true

# PRD-20260909-promotions-promo-batch2 (AC-001..004): unified read-only
# "already applied discounts" projection for Cart / Checkout / Order / Email /
# Webhook / Admin.
#
# Amounts follow the Batch-1 Appendix A 口径: only eligible promotion
# adjustments (`source_type = PromotionAction`, `eligible = true`) across the
# three tiers (order / line item / shipment) count. This fixes the legacy
# `OrderPromotion#amount` gap (it summed un-eligible competing adjustments too).
#
# Invariants (locked by contract specs):
#   * SUM(lines.amount) == order.discount_total
#   * line.amount == breakdown {items, order, shipping} sum
#   * serialization does NOT issue per-line SQL (batch query + in-memory group)
module PallasTrade
  module Promotions
    module Projection
      class DiscountProjection
        # One discount line per promotion, aggregated across adjustables.
        class Line
          attr_reader :order_promotion, :promotion, :adjustments, :currency

          def initialize(order:, order_promotion:, promotion:, adjustments:, currency:)
            @order = order
            @order_promotion = order_promotion
            @promotion = promotion
            @adjustments = adjustments
            @currency = currency
          end

          def id
            order_promotion&.prefixed_id || promotion.prefixed_id
          end

          def promotion_id
            promotion.prefixed_id
          end

          def name
            promotion.name
          end

          def description
            promotion.description
          end

          # The code actually used on this order (multi-code promos resolve to
          # the redeemed code; single-code promos return their `code`).
          def code
            promotion.code_for_order(@order)
          end

          def kind
            promotion.kind
          end

          def removable?
            promotion.coupon_code? && code.present?
          end

          def amount
            @amount ||= adjustments.sum { |a| a.amount.to_d }
          end

          def item_amount
            breakdown[:items]
          end

          def order_amount
            breakdown[:order]
          end

          def shipping_amount
            breakdown[:shipping]
          end

          def display_amount
            PallasTrade::Money.new(amount, currency: currency)
          end

          def breakdown
            @breakdown ||= begin
              sums = { items: 0.to_d, order: 0.to_d, shipping: 0.to_d }
              adjustments.each do |adjustment|
                sums[tier_for(adjustment)] += adjustment.amount.to_d
              end
              sums
            end
          end

          # Stable ordering key (order_promotion first, then promotion).
          def sort_key
            [order_promotion&.created_at || promotion.created_at, order_promotion&.id || promotion.id]
          end

          private

          def tier_for(adjustment)
            case adjustment.adjustable_type
            when 'PallasTrade::Shipment' then :shipping
            when 'PallasTrade::LineItem' then :items
            else :order
            end
          end
        end

        def self.for(order:)
          new(order: order).call
        end

        def initialize(order:)
          @order = order
        end

        def call
          return [] if @order.nil?

          lines = grouped_adjustments.map do |promotion_id, adjustments|
            promotion = adjustments.first.source&.promotion
            next if promotion.nil?

            Line.new(
              order: @order,
              order_promotion: order_promotions[promotion_id],
              promotion: promotion,
              adjustments: adjustments,
              currency: @order.currency
            )
          end.compact

          lines.sort_by(&:sort_key)
        end

        private

        # Single batched query for all three tiers (order / line item /
        # shipment) — no per-promotion or per-line SQL (PRD AC-011).
        def grouped_adjustments
          PallasTrade::Adjustment.
            where(
              order_id: @order.id,
              source_type: 'PallasTrade::PromotionAction',
              eligible: true
            ).
            includes(:adjustable, source: :promotion).
            group_by { |adjustment| adjustment.source&.promotion_id }.
            reject { |promotion_id, _| promotion_id.nil? }
        end

        def order_promotions
          @order_promotions ||= PallasTrade::OrderPromotion.
                                where(order_id: @order.id).
                                includes(:promotion).
                                index_by(&:promotion_id)
        end
      end
    end
  end
end
