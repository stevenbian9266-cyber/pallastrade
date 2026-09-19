# frozen_string_literal: true

# PALLAS-CUSTOM: PRD-20260919-checkout-结算页待支付订单再次支付重验（失效行剔除/优惠复核/金额变化提示）
#
# Promotions::RemoveApplication —— 「把一条促销从订单上摘除」的唯一原语：
#   ① 摘除 order_promotions 关联
#   ② 删除该促销动作产生的调整行（order / line_item / shipment 三级，按 source 定位）
#   ③ 释放该促销的 active 核销（PromotionRedemption reserved/committed → released，带 reason）
#   ④ 移除该促销动作自动添加的赠品行（CreateLineItems）
#   ⑤ 重算订单（OrderUpdater）
#
# 消费方：
#   * `PromotionHandler::Coupon#remove`（后台订单促销移除 / 购物车路径，reason: coupon_removed）
#   * `OrderCheckout::Revalidate`（补付重验：剔除商品后促销不再满足 → 摘除）
# 不新增第二套核销/调整行清理逻辑。
module PallasTrade
  module Promotions
    class RemoveApplication
      prepend PallasTrade::ServiceModule::Base

      DEFAULT_REASON = 'promotion_ineligible'

      # @param order [PallasTrade::Order]
      # @param promotion [PallasTrade::Promotion]
      # @param reason [String] 核销释放原因（审计）
      def call(order:, promotion:, reason: DEFAULT_REASON)
        return failure(nil, 'Order not found') if order.nil?
        return success(nil) if promotion.nil?

        action_ids = promotion.actions.pluck(:id)

        order.promotions.delete(promotion)
        order.all_adjustments.
          where(source_type: 'PallasTrade::PromotionAction', source_id: action_ids).
          destroy_all
        release_redemption(order, promotion, reason)
        remove_promotion_line_items(order, promotion)
        order.update_with_updater!

        success(promotion)
      end

      private

      # 该促销在本订单上的 active 核销 → 释放（幂等：终态行不动）
      def release_redemption(order, promotion, reason)
        redemption = PallasTrade::PromotionRedemption.
                     active.
                     find_by(promotion_id: promotion.id, order_id: order.id)
        return if redemption.nil?

        PallasTrade::Promotions::Redemption::Release.call(redemption, reason: reason)
      end

      # 促销动作自动加入的商品（如 BOGO 赠品）随促销一起移除
      def remove_promotion_line_items(order, promotion)
        action_ids = promotion.actions.
                     where(type: 'PallasTrade::Promotion::Actions::CreateLineItems').
                     pluck(:id)
        return if action_ids.empty?

        PallasTrade::PromotionActionLineItem.where(promotion_action: action_ids).find_each do |item|
          line_item = order.find_line_item_by_variant(item.variant)
          next if line_item.blank?

          PallasTrade.cart_remove_item_service.call(order: order, variant: item.variant, quantity: item.quantity)
        end
      end
    end
  end
end
