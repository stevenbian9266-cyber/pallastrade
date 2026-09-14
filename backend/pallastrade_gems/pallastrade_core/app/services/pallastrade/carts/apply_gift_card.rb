# frozen_string_literal: true

# PRD-20260914-checkout-cart-gift-cards-canonical（FR-002）：
# `cart_` 阶段的礼品卡**意图**持久化。
#
# 为什么不是"在车上应用礼品卡"：legacy 流程里购物车就是 Order，
# `order.apply_gift_card` 会**立即创建 store-credit payment 并占用礼品卡余额**；
# 而 canonical `pallastrade_carts` 没有 payments（资金只存在于 Order/Transaction）。
# 因此车阶段**零资金副作用** —— 只校验并记住意图，真正占用发生在提交生成 Order 时
# （`Carts::Submit` → `order.apply_gift_card` → `gift_card_apply_service`）。
#
# 错误码与 legacy `GiftCardsController` 完全一致，保证调用方语义不变。
module PallasTrade
  module Carts
    class ApplyGiftCard
      prepend PallasTrade::ServiceModule::Base

      METADATA_KEY = 'gift_card_code'
      NOT_FOUND = 'gift_card_not_found'
      EXPIRED = 'gift_card_expired'
      REDEEMED = 'gift_card_already_redeemed'
      # FR-005：权威 `GiftCards::Apply` 拒绝「同单混用礼品卡 + 店铺余额」
      # （`gift_card_using_store_credit_error`）→ 意图层互斥，避免提交时才失败。
      STORE_CREDIT_CONFLICT = 'gift_card_store_credit_conflict'

      def call(cart:, code:)
        return failure(cart, STORE_CREDIT_CONFLICT) if ApplyStoreCredit.intent?(cart)

        normalized = code.to_s.strip.downcase
        return failure(cart, NOT_FOUND) if normalized.blank?

        error = self.class.validate_code(cart.store, normalized)
        return failure(cart, error) if error

        cart.private_metadata = (cart.private_metadata || {}).merge(METADATA_KEY => normalized)
        cart.save!
        success(cart)
      rescue ActiveRecord::RecordInvalid => e
        failure(cart, e.record.errors.full_messages.to_sentence)
      end

      # 可用 → nil；不可用 → 错误码（与 legacy 端点一致，提交路径复用同一校验）。
      def self.validate_code(store, code)
        normalized = code.to_s.strip.downcase
        return NOT_FOUND if normalized.blank?

        gift_card = store.gift_cards.find_by(code: normalized)
        return NOT_FOUND if gift_card.nil?
        return EXPIRED if gift_card.expired?
        return REDEEMED if gift_card.redeemed?

        nil
      end
    end
  end
end
