# frozen_string_literal: true

# PRD-20260909-promotions-promo-batch2 (方案A): canonical discount payload used
# by Cart / Order / Admin Order / Checkout serializers. Shape is identical
# everywhere so `SUM(discounts[].amount) == discount_total` can be asserted and
# clients only implement one renderer.
#
# Money gating: with `hide_prices`, the whole `discounts` field is nulled
# (same convention as CheckoutSerializer's previous behaviour), so gated guests
# never receive amounts nor discount identities.
module PallasTrade
  module Api
    module V3
      module DiscountRendering
        DISCOUNT_LINE_TYPE = 'Array<{ id: string, promotion_id: string, name: string, ' \
                             'description: string | null, code: string | null, kind: string, ' \
                             'amount: string | null, display_amount: string | null, ' \
                             'breakdown: { items: string, order: string, shipping: string } | null, ' \
                             'removable: boolean }>'

        def discounts_payload(order)
          return nil if params[:hide_prices]
          return [] if order.nil?

          PallasTrade::Promotions::Projection::DiscountProjection.for(order: order).map do |line|
            discount_line_payload(line)
          end
        end

        def discount_line_payload(line)
          {
            id: line.id,
            promotion_id: line.promotion_id,
            name: line.name,
            description: line.description,
            code: line.code,
            kind: line.kind,
            amount: line.amount.to_s,
            display_amount: line.display_amount.to_s,
            breakdown: {
              items: line.item_amount.to_s,
              order: line.order_amount.to_s,
              shipping: line.shipping_amount.to_s
            },
            removable: line.removable?
          }
        end
      end
    end
  end
end
