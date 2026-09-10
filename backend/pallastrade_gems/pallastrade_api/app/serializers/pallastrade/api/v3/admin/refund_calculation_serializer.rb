# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch4b-refund-allocation (FR-003)
#
# 「退款计算预览」只读序列化（Admin 只读扁平风格，同 batch3c）：
# 渲染 `Promotions::Allocation::RefundPreview::Result`（非 AR 记录，PORO 渲染）。
module PallasTrade
  module Api
    module V3
      module Admin
        class RefundCalculationSerializer < BaseSerializer
          typelize order_id: :string, currency: [:string, { nullable: true }],
                   available: :boolean,
                   line_items: 'RefundCalculationLine[]', promotions: 'RefundCalculationPromotion[]',
                   totals: 'RefundCalculationTotals'

          attribute :order_id, &:order_prefixed_id

          attributes :currency, :available

          attribute :line_items do |preview|
            preview.line_items.map { |line| line_payload(line) }
          end

          attribute :promotions do |preview|
            preview.promotions.map { |promotion| promotion_payload(promotion) }
          end

          attribute :totals do |preview|
            totals_payload(preview.totals)
          end

          private

          def line_payload(line)
            {
              line_item_id: line.line_item_prefixed_id,
              sku: line.sku,
              name: line.name,
              quantity: line.quantity,
              return_quantity: line.return_quantity,
              original_amount: money(line.original_amount),
              allocated_discount: money(line.allocated_discount),
              allocated_discount_breakdown: line.breakdown.transform_values { |value| money(value) },
              pre_tax_amount: money(line.pre_tax_amount),
              refundable_amount: line.refundable_amount.nil? ? nil : money(line.refundable_amount),
              refundable_source: line.refundable_source
            }
          end

          def promotion_payload(promotion)
            {
              promotion_id: promotion[:promotion_prefixed_id],
              order_promotion_id: promotion[:order_promotion_prefixed_id],
              name: promotion[:name],
              code: promotion[:code],
              original_discount: money(promotion[:original_discount]),
              allocated_discount: money(promotion[:allocated_discount]),
              balanced: promotion[:balanced],
              basis_totals: promotion[:basis_totals].transform_values { |value| money(value) }
            }
          end

          def totals_payload(totals)
            {
              original_amount: money(totals[:original_amount]),
              allocated_discount: money(totals[:allocated_discount]),
              refundable_amount: money(totals[:refundable_amount]),
              refundable_complete: totals[:refundable_complete],
              currency: totals[:currency]
            }
          end

          def money(value)
            value.nil? ? nil : format('%.2f', value)
          end
        end
      end
    end
  end
end
