# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch4b-refund-allocation (FR-002/FR-003, PR-P6-3)
#
# 售后金额预览（只读）：把
#   * 折前原金额   = `line_item.amount`
#   * 分摊优惠     = `Allocation::AdjustmentAllocation`（促销维度，含 basis 明细）
#   * 可退金额     = `ReturnItem#refund_amount_calculator`（**唯一权威**，REV-P6-3 冻结）
# 组装成「原金额 / 分摊优惠 / 可退金额」三件套，供 Admin API 与后台订单页消费。
#
# 边界：
#   * **不复制**退款公式（不重写 `DefaultRefundAmount`）：可退金额一律通过内存 ReturnItem 调权威；
#   * 行级明细无 inventory unit（未发货/历史数据）时 `refundable_amount = nil` + `refundable_source = 'unavailable'`，
#     绝不臆造金额；
#   * 不写库、不创建 Refund/ReturnItem、不跑 Promotion Engine。
module PallasTrade
  module Promotions
    module Allocation
      class RefundPreview
        SOURCE_AUTHORITY = 'authority'
        SOURCE_UNAVAILABLE = 'unavailable'
        SOURCE_ZERO = 'zero'
        ZERO = BigDecimal('0')

        LinePreview = Struct.new(
          :line_item_id, :line_item_prefixed_id, :sku, :name, :quantity, :return_quantity,
          :original_amount, :allocated_discount, :breakdown, :pre_tax_amount,
          :refundable_amount, :refundable_source,
          keyword_init: true
        )

        class Result
          attr_reader :order_id, :order_prefixed_id, :currency, :line_items, :promotions, :available

          # rubocop:disable Metrics/ParameterLists -- ECS 值对象字段齐备（与 API 载荷一一对应）
          def initialize(order_id:, order_prefixed_id:, currency:, line_items:, promotions:, available: true)
            @order_id = order_id
            @order_prefixed_id = order_prefixed_id
            @currency = currency
            @line_items = line_items.freeze
            @promotions = promotions.freeze
            @available = available
          end
          # rubocop:enable Metrics/ParameterLists

          def available? = available

          def total_original
            line_items.sum(ZERO, &:original_amount)
          end

          def total_allocated
            line_items.sum(ZERO, &:allocated_discount)
          end

          def total_refundable
            line_items.sum(ZERO) { |line| line.refundable_amount || ZERO }
          end

          def refundable_complete?
            line_items.none? { |line| line.refundable_amount.nil? && line.return_quantity.to_i.positive? }
          end

          def totals
            {
              original_amount: total_original,
              allocated_discount: total_allocated,
              refundable_amount: total_refundable,
              refundable_complete: refundable_complete?,
              currency: currency
            }
          end
        end

        def self.call(order:, quantities: {})
          new(order: order, quantities: quantities).call
        end

        def initialize(order:, quantities: {})
          @order = order
          @quantities = normalize_quantities(quantities)
        end

        def call
          return unavailable_result if order.nil?

          allocation = AdjustmentAllocation.for(order: order)

          Result.new(
            order_id: order.id,
            order_prefixed_id: order.prefixed_id,
            currency: order.currency,
            line_items: preview_lines(allocation),
            promotions: promotion_summaries(allocation)
          )
        rescue StandardError => e
          Rails.logger.error(
            "[Promotions::Allocation::RefundPreview] order=#{order&.id} failed: #{e.class} #{e.message}"
          )
          unavailable_result
        end

        private

        attr_reader :order, :quantities

        def unavailable_result
          Result.new(order_id: order&.id, order_prefixed_id: order&.prefixed_id, currency: order&.currency,
                     line_items: [], promotions: [], available: false)
        end

        def normalize_quantities(raw)
          return {} if raw.blank?

          raw.to_h.each_with_object({}) do |(key, value), result|
            line_item_id = line_item_id_from(key)
            result[line_item_id] = value.to_i if line_item_id
          end
        end

        # 同时接受整型 id 与 prefixed id（`li_…`）。
        def line_item_id_from(key)
          string = key.to_s
          return string.to_i if string.match?(/\A\d+\z/)
          return nil unless PallasTrade::PrefixedId.prefixed_id?(string)

          PallasTrade::PrefixedId.decode_prefixed_id(string)
        end

        def preview_lines(allocation)
          order.line_items.map do |line_item|
            return_quantity = requested_quantity(line_item)
            refundable, source = refundable_amount_for(line_item, return_quantity)

            LinePreview.new(
              line_item_id: line_item.id,
              line_item_prefixed_id: line_item.prefixed_id,
              sku: line_item.sku,
              name: line_item.name,
              quantity: line_item.quantity,
              return_quantity: return_quantity,
              original_amount: line_item.amount.to_d,
              allocated_discount: allocation.allocated_for_line_item(line_item.id),
              breakdown: allocation.basis_totals_for_line_item(line_item.id),
              pre_tax_amount: line_item.pre_tax_amount.to_d,
              refundable_amount: refundable,
              refundable_source: source
            )
          end
        end

        def promotion_summaries(allocation)
          allocation.promotion_totals.map do |total|
            row = order_promotion_rows[total[:promotion_id]]

            {
              promotion_id: total[:promotion_id],
              promotion_prefixed_id: row&.promotion&.prefixed_id,
              order_promotion_id: total[:order_promotion_id] || row&.id,
              order_promotion_prefixed_id: row&.prefixed_id,
              name: row&.name,
              code: row&.code,
              original_discount: total[:original_amount],
              allocated_discount: total[:allocated_amount],
              balanced: total[:balanced],
              basis_totals: total[:basis_totals]
            }
          end
        end

        # batch4a：名称/码快照优先（冻结订单不受当前促销定义漂移）。
        def order_promotion_rows
          @order_promotion_rows ||= order.order_promotions.includes(:promotion).index_by(&:promotion_id)
        end

        def requested_quantity(line_item)
          value = quantities[line_item.id]
          return line_item.quantity if value.nil?

          value.clamp(0, line_item.quantity)
        end

        # 可退金额的唯一权威调用点：内存 ReturnItem → `DefaultRefundAmount`（不写库、不复制公式）。
        def refundable_amount_for(line_item, return_quantity)
          return [ZERO, SOURCE_ZERO] if return_quantity.to_i.zero?

          inventory_unit = line_item.inventory_units.order(:id).first
          return [nil, SOURCE_UNAVAILABLE] if inventory_unit.nil?

          return_item = PallasTrade::ReturnItem.new(inventory_unit: inventory_unit)
          return_item.return_quantity = return_quantity
          return_item.set_default_pre_tax_amount

          [return_item.pre_tax_amount.to_d, SOURCE_AUTHORITY]
        end
      end
    end
  end
end
