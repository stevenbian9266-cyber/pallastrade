# frozen_string_literal: true

# PRD-20260914-checkout-cart-gift-cards-canonical（FR-003）：
# 从 `cart_` 移除礼品卡意图 —— 幂等（无卡 / 码不匹配也返回成功）。
module PallasTrade
  module Carts
    class RemoveGiftCard
      prepend PallasTrade::ServiceModule::Base

      def call(cart:, code: nil)
        current = (cart.private_metadata || {})[ApplyGiftCard::METADATA_KEY]
        return success(cart) if current.blank?

        # `code` 可省略（DELETE 只带购物车）；带了但不等则视为幂等空操作
        normalized = code.to_s.strip.downcase
        return success(cart) if normalized.present? && normalized != current

        cart.private_metadata = (cart.private_metadata || {}).except(ApplyGiftCard::METADATA_KEY)
        cart.save!
        success(cart)
      rescue ActiveRecord::RecordInvalid => e
        failure(cart, e.record.errors.full_messages.to_sentence)
      end
    end
  end
end
