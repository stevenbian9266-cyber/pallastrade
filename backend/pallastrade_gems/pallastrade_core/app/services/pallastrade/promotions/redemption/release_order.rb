# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3a-redemption-ledger (FR-008, G4)
#
# 订单取消时释放该订单全部 active 核销（幂等）：状态 → released，
# 回退占用中的一次性码（model#release! 内处理），并逐个发布 released 事件。
module PallasTrade
  module Promotions
    module Redemption
      class ReleaseOrder
        DEFAULT_REASON = 'order_canceled'

        def self.call(order, reason: DEFAULT_REASON)
          new(order, reason: reason).call
        end

        def initialize(order, reason: DEFAULT_REASON)
          @order = order
          @reason = reason
        end

        def call
          order.promotion_redemptions.active.includes(:coupon_code).map do |redemption|
            Release.call(redemption, reason: reason)
          end
        end

        private

        attr_reader :order, :reason
      end
    end
  end
end
