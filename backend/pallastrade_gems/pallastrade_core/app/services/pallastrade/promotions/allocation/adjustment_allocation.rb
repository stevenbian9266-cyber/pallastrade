# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch4b-refund-allocation (FR-001, PR-P6-2)
#
# 促销折扣**只读分摊投影**（架构 §57 AdjustmentAllocation 语义）：
#   行级促销调整  → 直接归该行（basis = line_item）
#   订单级促销调整 → 按行占比分摊（basis = order_prorata），分母 = order.pre_tax_item_amount
#   运费级促销调整 → 同按行占比（basis = shipment_prorata）
#
# 边界（REQ/PRD R1-R10）：
#   * **只读**：不写库、不创建 Refund/ReturnItem、不跑 Promotion Engine、不做 eligibility 判定；
#   * **金额锚点**：per promotion 的折扣总额优先取 batch4a 成交快照（`order_promotions.total_amount`），
#     未冻结时退回 batch2 统一投影（`DiscountProjection::Line#amount`）——两者同口径；
#   * **守恒**：2 位小数舍入后把余数补给最大分摊行，保证 `Σ == 锚点`（超出舍入量级的差异不掩盖，
#     该促销标记 `balanced: false`）。
#
# 退款金额本身**不在此处计算**：唯一权威是 `Calculator::Returns::DefaultRefundAmount`
# （REV-P6-3 审计冻结，见 pallastrade-pricing skill §224-229）。
module PallasTrade
  module Promotions
    module Allocation
      class AdjustmentAllocation
        BASIS_LINE_ITEM = 'line_item'
        BASIS_ORDER_PRORATA = 'order_prorata'
        BASIS_SHIPMENT_PRORATA = 'shipment_prorata'
        BASES = [BASIS_LINE_ITEM, BASIS_ORDER_PRORATA, BASIS_SHIPMENT_PRORATA].freeze
        ZERO = BigDecimal('0')

        # 2 位小数舍入可产生的最大余量（用于区分"舍入余数"与"真实数据不一致"）。
        MAX_ROUNDING_REMAINDER = BigDecimal('0.05')

        Line = Struct.new(
          :promotion_id, :order_promotion_id, :line_item_id, :allocation_basis, :allocated_amount,
          keyword_init: true
        ) do
          def amount = allocated_amount

          def to_h
            {
              promotion_id: promotion_id,
              order_promotion_id: order_promotion_id,
              line_item_id: line_item_id,
              allocation_basis: allocation_basis,
              allocated_amount: format('%.2f', allocated_amount)
            }
          end
        end

        class Result
          attr_reader :lines, :promotion_totals, :currency

          def initialize(lines:, promotion_totals:, currency:)
            @lines = lines.freeze
            @promotion_totals = promotion_totals.freeze
            @currency = currency
          end

          def balanced?
            promotion_totals.all? { |total| total[:balanced] }
          end

          def total_allocated
            promotion_totals.sum(ZERO) { |total| total[:allocated_amount] }
          end

          def total_original
            promotion_totals.sum(ZERO) { |total| total[:original_amount] }
          end

          def allocated_for_line_item(line_item_id)
            lines.select { |line| line.line_item_id == line_item_id }.sum(ZERO, &:allocated_amount)
          end

          def allocated_for_promotion(promotion_id)
            lines.select { |line| line.promotion_id == promotion_id }.sum(ZERO, &:allocated_amount)
          end

          def basis_totals_for_line_item(line_item_id)
            BASES.index_with do |basis|
              lines.select { |line| line.line_item_id == line_item_id && line.allocation_basis == basis }.
                sum(ZERO, &:allocated_amount)
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
          return empty_result if order.nil?

          lines = []
          totals = []

          projection_lines.each do |projection_line|
            anchor = anchor_total(projection_line)
            allocated = allocate_line(projection_line, anchor, lines)
            totals << allocated.merge(original_amount: anchor)
          end

          Result.new(lines: lines, promotion_totals: totals, currency: order.currency)
        rescue StandardError => e
          Rails.logger.error(
            "[Promotions::Allocation::AdjustmentAllocation] order=#{order&.id} failed: #{e.class} #{e.message}"
          )
          empty_result
        end

        private

        attr_reader :order

        def empty_result
          Result.new(lines: [], promotion_totals: [], currency: order&.currency)
        end

        def projection_lines
          @projection_lines ||= PallasTrade::Promotions::Projection::DiscountProjection.for(order: order).to_a
        end

        # 折扣总额锚点：冻结快照优先（batch4a），未冻结退回投影（batch2）。取绝对值。
        def anchor_total(projection_line)
          frozen = projection_line.order_promotion
          value = if frozen&.frozen?
                    frozen.total_amount.to_d
                  else
                    projection_line.amount.to_d
                  end
          value.abs.round(2)
        end

        def allocate_line(projection_line, anchor, lines)
          rounded = round_with_remainder(raw_allocations(projection_line), anchor)
          basis_totals = BASES.index_with { ZERO }

          rounded.each do |(line_item_id, basis), amount|
            lines << Line.new(
              promotion_id: projection_line.promotion.id,
              order_promotion_id: projection_line.order_promotion&.id,
              line_item_id: line_item_id,
              allocation_basis: basis,
              allocated_amount: amount
            )
            basis_totals[basis] += amount
          end

          allocated_amount = basis_totals.values.sum(ZERO)

          {
            promotion_id: projection_line.promotion.id,
            order_promotion_id: projection_line.order_promotion&.id,
            allocated_amount: allocated_amount,
            basis_totals: basis_totals,
            balanced: allocated_amount == anchor
          }
        end

        # key = [line_item_id, basis] → 精确（未舍入）分摊额。
        def raw_allocations(projection_line)
          raw = Hash.new { |hash, key| hash[key] = ZERO }

          projection_line.adjustments.each do |adjustment|
            amount = adjustment.amount.to_d.abs
            next if amount.zero?

            case adjustment.adjustable_type
            when 'PallasTrade::LineItem'
              raw[[adjustment.adjustable_id, BASIS_LINE_ITEM]] += amount
            when 'PallasTrade::Shipment'
              add_prorated(raw, amount, BASIS_SHIPMENT_PRORATA)
            else
              add_prorated(raw, amount, BASIS_ORDER_PRORATA)
            end
          end

          raw
        end

        def add_prorated(raw, amount, basis)
          line_shares.each do |line_item, share|
            raw[[line_item.id, basis]] += amount * share
          end
        end

        # R3：行占比（分母 order.pre_tax_item_amount）；为 0 或异常时全额落到最大行，保证守恒。
        def line_shares
          @line_shares ||= begin
            items = order.line_items.to_a
            base = order.pre_tax_item_amount.to_d

            if items.empty?
              {}
            elsif base.zero?
              { items.max_by { |item| [item.amount.to_d, -item.id] } => BigDecimal('1') }
            else
              items.to_h { |item| [item, item.pre_tax_amount.to_d / base] }
            end
          end
        end

        # 2 位小数舍入；舍入余量（≤ MAX_ROUNDING_REMAINDER）补给金额最大的分摊行 → Σ == 锚点。
        def round_with_remainder(raw, anchor)
          rounded = raw.transform_values { |value| value.round(2) }
          remainder = anchor - rounded.values.sum(ZERO)
          return rounded if remainder.zero? || remainder.abs > MAX_ROUNDING_REMAINDER

          key = rounded.max_by { |(line_item_id, _basis), value| [value.abs, -line_item_id.to_i] }&.first
          rounded[key] = (rounded[key] + remainder).round(2) if key

          rounded
        end
      end
    end
  end
end
