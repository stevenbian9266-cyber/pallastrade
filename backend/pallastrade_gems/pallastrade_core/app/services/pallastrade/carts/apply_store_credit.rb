# frozen_string_literal: true

# PRD-20260914-checkout-cart-store-credits-canonical（FR-002）：
# `cart_` 阶段的**店铺余额意图**持久化。
#
# 为什么不是"在车上扣余额"：legacy 流程里购物车就是 Order，
# `Checkout::AddStoreCredit` 会**立即创建 store-credit payment（state: checkout）**；
# 而 canonical `pallastrade_carts` 没有 payments（资金只存在于 Order/Transaction）。
# 因此车阶段**零资金副作用** —— 只校验并记住意图，真正占用发生在提交生成 Order 时
# （`Carts::Submit#apply_store_credit!` → `PallasTrade.checkout_add_store_credit_service`）。
#
# 与礼品卡互斥：权威 `GiftCards::Apply` 明确拒绝"同单混用礼品卡 + 店铺余额"
# （`:gift_card_using_store_credit_error`），故在意图层就互斥，避免提交时才失败。
module PallasTrade
  module Carts
    class ApplyStoreCredit
      prepend PallasTrade::ServiceModule::Base

      METADATA_KEY = 'store_credit_amount'
      REQUIRES_LOGIN = 'store_credit_requires_login'
      NOT_AVAILABLE = 'store_credit_not_available'
      INVALID_AMOUNT = 'store_credit_invalid_amount'
      GIFT_CARD_CONFLICT = 'store_credit_gift_card_conflict'

      def call(cart:, amount: nil)
        return failure(cart, REQUIRES_LOGIN) if cart.user.blank?
        if (cart.private_metadata || {})[ApplyGiftCard::METADATA_KEY].present?
          return failure(cart, GIFT_CARD_CONFLICT)
        end

        # 无可用余额（含币种不符）→ 与 legacy 服务同口径直接拒绝（legacy：
        # `error_user_does_not_have_any_store_credits`），无论是否显式给了金额。
        available = available_total(cart)
        return failure(cart, NOT_AVAILABLE) unless available.positive?

        requested = parse_amount(amount)
        return failure(cart, INVALID_AMOUNT) if requested == :invalid

        # 省略金额 = 用尽可用余额：此刻就把金额固化成字符串，便于序列化展示；
        # 提交时权威服务仍会按 `min(金额, outstanding_balance)` 收敛。
        requested = available if requested.nil?

        cart.private_metadata = (cart.private_metadata || {}).merge(METADATA_KEY => requested.to_s('F'))
        cart.save!
        success(cart)
      rescue ActiveRecord::RecordInvalid => e
        failure(cart, e.record.errors.full_messages.to_sentence)
      end

      # 购物车上的余额意图（BigDecimal）；无意图 → nil。
      def self.requested_amount(cart)
        raw = (cart.private_metadata || {})[METADATA_KEY]
        return nil if raw.blank?

        BigDecimal(raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def self.intent?(cart)
        (cart.private_metadata || {})[METADATA_KEY].present?
      end

      private

      def parse_amount(amount)
        return nil if amount.nil? || amount.to_s.strip.empty?

        parsed = BigDecimal(amount.to_s)
        parsed.positive? ? parsed : :invalid
      rescue ArgumentError, TypeError
        :invalid
      end

      def available_total(cart)
        cart.user.store_credits.for_store(cart.store).available.where(currency: cart.currency).sum(&:amount_remaining)
      end
    end
  end
end
