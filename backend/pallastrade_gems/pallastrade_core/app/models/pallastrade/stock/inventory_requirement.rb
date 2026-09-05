# frozen_string_literal: true

module PallasTrade
  module Stock
    # INV-P3-2 (PRD-20260905-shipping-库存事务集成与预留生命周期-p3-..., FR-003/004):
    # InventoryRequirement —— 判定一个 line_item 是否需要 Reservation（REQUIRED/NOT_REQUIRED）。
    #
    # 语义（与 StockReservations::Reserve#build_targets 的豁免保持一致）：
    #   - NOT_REQUIRED：不 track 库存 / digital（should_track_inventory?=false）、
    #     preorder、或该 variant 无可"非 backorderable 活跃 stock_item"可预留
    #     （全 backorderable → oversell 走 Quantifier#can_supply?，不需要 reservation）。
    #   - REQUIRED：track 且存在可预留 stock_item —— 即使当前 count_on_hand=0（缺货），
    #     也应视为 REQUIRED：由 Start 的 Reserve 门在无法预留时返回 INSUFFICIENT_STOCK。
    # 仅作 policy/service，不建表（FR-004）。
    class InventoryRequirement
      def self.required?(line_item)
        new.required?(line_item)
      end

      def required?(line_item)
        return false unless PallasTrade::Config[:stock_reservations_enabled]

        variant = line_item.variant
        return false if variant.nil?
        return false unless variant.should_track_inventory?
        return false if variant.preorder?

        reservable_stock_item?(variant)
      end

      private

      def reservable_stock_item?(variant)
        variant.stock_items.any? do |si|
          si.stock_location&.active? && !si.backorderable?
        end
      end
    end
  end
end
