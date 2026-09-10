# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3a-redemption-ledger (FR-007, D3/D5)
#
# 下单核销入口（`order.complete` 短事务内调用；替代测试外的 `use_all_coupon_codes` 占用职责）：
#   1. 对订单上**有 eligible 促销调整**的每个促销 Reserve + Commit（同事务，幂等）
#   2. 多码促销：核销时原子占用一次性码（unused → used + 关联订单）
#   3. 不再 eligible 的促销：脱离其码（等价旧 clear_all_unused 语义）
module PallasTrade
  module Promotions
    module Redemption
      class FinalizeOrder
        def self.call(order)
          new(order).call
        end

        def initialize(order)
          @order = order
        end

        def call
          redemptions = eligible_promotions.map { |promotion| finalize(promotion) }
          detach_stale_coupon_codes
          redemptions
        end

        private

        attr_reader :order

        def eligible_promotions
          action_ids = order.all_adjustments.promotion.eligible.pluck(:source_id).compact.uniq
          return [] if action_ids.empty?

          promotion_ids = PallasTrade::PromotionAction.where(id: action_ids).pluck(:promotion_id).compact.uniq
          PallasTrade::Promotion.where(id: promotion_ids)
        end

        def finalize(promotion)
          coupon_code = coupon_code_for(promotion)
          redemption = Reserve.call(order: order, promotion: promotion, coupon_code: coupon_code)
          redemption = Commit.call(redemption)
          occupy_coupon_code(coupon_code)
          redemption
        end

        def coupon_code_for(promotion)
          return nil unless promotion.multi_codes?

          promotion.coupon_codes.find_by(order_id: order.id)
        end

        def occupy_coupon_code(coupon_code)
          return if coupon_code.blank?
          return if coupon_code.state.to_s == 'used' && coupon_code.order_id == order.id

          coupon_code.apply_order!(order)
        end

        # 等价旧 `CouponCodesHandler#clear_all_unused`：把已不在本单生效的码脱离订单
        # （保留 unused 状态，不做消耗）。
        def detach_stale_coupon_codes
          promotion_ids = eligible_promotions.map(&:id)
          PallasTrade::CouponCode.where(order_id: order.id).
            where.not(promotion_id: promotion_ids).
            find_each(&:detach_from_order)
        end
      end
    end
  end
end
