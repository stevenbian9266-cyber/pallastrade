# frozen_string_literal: true

# PRD-20260914-checkout-cart-store-credits-canonical（FR-003）：
# 从 `cart_` 移除店铺余额意图 —— 幂等（无意图也返回成功）。
module PallasTrade
  module Carts
    class RemoveStoreCredit
      prepend PallasTrade::ServiceModule::Base

      def call(cart:)
        return success(cart) unless ApplyStoreCredit.intent?(cart)

        cart.private_metadata = (cart.private_metadata || {}).except(ApplyStoreCredit::METADATA_KEY)
        cart.save!
        success(cart)
      rescue ActiveRecord::RecordInvalid => e
        failure(cart, e.record.errors.full_messages.to_sentence)
      end
    end
  end
end
