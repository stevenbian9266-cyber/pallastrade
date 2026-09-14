# frozen_string_literal: true

# PRD-20260914-checkout-cart-discount-codes-canonical（FR-002/FR-003）：
# `cart_` 阶段的优惠码**意图**持久化。
#
# 语义要点（见 pallastrade-promotions Skill）：
#   * 应用码**不消耗码** —— 占用/核销由 `PromotionRedemption`（reserve/commit/release）负责；
#   * 码大小写不敏感，规范化后存储（`downcase` + `strip`）；
#   * 查找走 `Promotion.with_coupon_code`（单码优先，否则看 generated `CouponCode`）。
#
# 持久化位置：`cart.private_metadata['discount_code']`（不新增数据库列；`private_*`
# 不对外序列化，避免把「意图」暴露成公开字段）。
module PallasTrade
  module Carts
    class ApplyDiscountCode
      prepend PallasTrade::ServiceModule::Base

      METADATA_KEY = 'discount_code'
      NOT_FOUND = 'coupon_code_not_found'
      EXPIRED = 'coupon_code_expired'

      def call(cart:, code:)
        normalized = code.to_s.strip.downcase
        return failure(cart, NOT_FOUND) if normalized.blank?

        validation = validate_code(cart.store, normalized)
        return failure(cart, validation) if validation

        cart.private_metadata = (cart.private_metadata || {}).merge(METADATA_KEY => normalized)
        cart.save!
        success(cart)
      rescue ActiveRecord::RecordInvalid => e
        failure(cart, e.record.errors.full_messages.to_sentence)
      end

      # 码是否可用于该商店；可用 → nil，不可用 → 错误码（与 PromotionHandler 口径一致）
      def self.validate_code(store, code)
        normalized = code.to_s.strip.downcase
        return NOT_FOUND if normalized.blank?

        promotion = store.promotions.with_coupon_code(normalized)
        return NOT_FOUND if promotion.nil?
        return EXPIRED if promotion.expired?

        nil
      end

      private

      def validate_code(store, normalized)
        self.class.validate_code(store, normalized)
      end
    end
  end
end
