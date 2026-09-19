# frozen_string_literal: true

# PALLAS-CUSTOM: PRD-20260919-checkout-结算页待支付订单再次支付重验（失效行剔除/优惠复核/金额变化提示）
#
# 共享「行是否仍可售」判定 —— 唯一权威谓词。
# 消费方：
#   * 购物车剔行 `PallasTrade::CartLegacy::RemoveOutOfStockItems`
#   * 订单补付重验 `PallasTrade::OrderCheckout::Revalidate`
# 两处共用这一份实现，避免「购物车口径」与「订单口径」漂移（判废原因也共用一套枚举）。
module PallasTrade
  module Catalog
    module LineItemAvailability
      # 判废原因（对前台可解释；前端按 code 映射文案）
      REASON_MISSING_VARIANT = 'missing_variant'
      REASON_DELETED = 'deleted'
      REASON_ARCHIVED = 'archived'
      REASON_DISCONTINUED = 'discontinued'
      REASON_OUT_OF_STOCK = 'out_of_stock'

      REASONS = [
        REASON_MISSING_VARIANT, REASON_DELETED, REASON_ARCHIVED,
        REASON_DISCONTINUED, REASON_OUT_OF_STOCK
      ].freeze

      module_function

      # @param line_item [PallasTrade::LineItem]
      # @return [String, nil] 不可售原因；nil 表示仍可售
      def unavailable_reason(line_item)
        variant = line_item.variant
        return REASON_MISSING_VARIANT if variant.nil?

        product = variant.product
        return REASON_DELETED if product.nil? || product.deleted?
        return REASON_ARCHIVED unless product.active?
        return REASON_DISCONTINUED if product.discontinued? || variant.discontinued?
        return REASON_OUT_OF_STOCK if line_item.insufficient_stock?

        nil
      end

      def available?(line_item)
        unavailable_reason(line_item).nil?
      end

      # 库存类原因（购物车/订单文案分流用）
      def stock_reason?(reason)
        [REASON_OUT_OF_STOCK, REASON_MISSING_VARIANT].include?(reason)
      end
    end
  end
end
