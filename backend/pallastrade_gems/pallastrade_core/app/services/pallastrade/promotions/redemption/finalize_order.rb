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
          redemptions = eligible_promotions.filter_map { |promotion| finalize(promotion) }
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

        # FR-001：占用的临界区在 `promotion.with_lock` 内 —— 同一促销并发核销被串行化，
        # 锁内**重查** usage_limit（基于 ledger），超限则不写核销行也不占码，发布 overshoot
        # 事件（订单已成交，不因名额竞争阻断资金/履约；少计数但不伪计数）。
        def finalize(promotion)
          coupon_code = coupon_code_for(promotion)
          redemption = nil

          promotion.with_lock do
            if promotion.usage_limit_exceeded?(order)
              publish_limit_overshoot(promotion)
              next
            end

            redemption = Reserve.call(order: order, promotion: promotion, coupon_code: coupon_code)
            redemption = Commit.call(redemption)
          end

          return nil if redemption.nil?

          occupy_coupon_code(coupon_code)
          redemption
        end

        def coupon_code_for(promotion)
          return nil unless promotion.multi_codes?

          promotion.coupon_codes.find_by(order_id: order.id)
        end

        # FR-001：多码占用在行锁内校验与写入（同一码不可被两单占用）。
        # 已被其它订单占用时：不阻塞订单，发布冲突事件供运营/审计跟进。
        def occupy_coupon_code(coupon_code)
          return if coupon_code.blank?

          coupon_code.with_lock do
            coupon_code.reload
            if coupon_code.state.to_s == 'used' && coupon_code.order_id != order.id
              publish_code_conflict(coupon_code)
              next
            end

            coupon_code.apply_order!(order) unless coupon_code.order_id == order.id && coupon_code.state.to_s == 'used'
          end
        end

        def publish_limit_overshoot(promotion)
          Rails.logger.warn(
            "[promotions.redemptions] usage limit reached at completion " \
            "order=#{order.prefixed_id} promotion=#{promotion.prefixed_id} " \
            "committed=#{promotion.credits_count} limit=#{promotion.usage_limit}"
          )
          order.publish_event(
            'promotion.redemption_limit_overshoot',
            'order_id' => order.prefixed_id,
            'promotion_id' => promotion.prefixed_id,
            'usage_limit' => promotion.usage_limit,
            'committed_count' => promotion.credits_count
          )
        end

        def publish_code_conflict(coupon_code)
          Rails.logger.warn(
            "[promotions.redemptions] coupon code already occupied by another order " \
            "order=#{order.prefixed_id} code=#{coupon_code.code} holder=#{coupon_code.order_id}"
          )
          order.publish_event(
            'promotion.redemption_code_conflict',
            'order_id' => order.prefixed_id,
            'promotion_id' => coupon_code.promotion_id,
            'coupon_code' => coupon_code.code
          )
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
