# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3a-redemption-ledger (FR-004, D5)
#
# 幂等创建占用行：同一 (promotion, order) 已存在 active 行时直接返回，不做二次写入。
# 唯一约束冲突（并发）回退为读取既有行；其它情况抛出并让外层事务回滚（下单失败
# 优于半占用）。
module PallasTrade
  module Promotions
    module Redemption
      class Reserve
        def self.call(order:, promotion:, coupon_code: nil)
          new(order: order, promotion: promotion, coupon_code: coupon_code).call
        end

        def initialize(order:, promotion:, coupon_code: nil)
          @order = order
          @promotion = promotion
          @coupon_code = coupon_code
        end

        def call
          existing = active_redemption
          return existing if existing

          PallasTrade::PromotionRedemption.create!(
            store: order.store,
            promotion: promotion,
            order: order,
            user: order.user,
            coupon_code: resolved_coupon_code,
            state: 'reserved',
            amount: amount,
            currency: order.currency,
            reserved_at: Time.current
          )
        rescue ActiveRecord::RecordNotUnique
          active_redemption || raise
        end

        private

        attr_reader :order, :promotion, :coupon_code

        def active_redemption
          PallasTrade::PromotionRedemption.active.find_by(promotion_id: promotion.id, order_id: order.id)
        end

        # 多码促销：订单在购物车阶段已把码关联到订单（只关联不消耗），核销时取回。
        def resolved_coupon_code
          return coupon_code if coupon_code.present?
          return nil unless promotion.multi_codes?

          promotion.coupon_codes.find_by(order_id: order.id)
        end

        # 金额口径沿用批次1 附录 A：仅统计 eligible 促销调整（不新增计算逻辑）。
        def amount
          order.all_adjustments.promotion.eligible.
            where(source_id: promotion.actions.select(:id)).
            sum(:amount)
        end
      end
    end
  end
end
