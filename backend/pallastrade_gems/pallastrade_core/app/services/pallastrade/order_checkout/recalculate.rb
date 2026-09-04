# frozen_string_literal: true

require 'digest'

# PALLAS-CUSTOM: CHK-P1-2 (PRD-20260903-checkout-chk-p1-1 §12)
module PallasTrade
  module OrderCheckout
    # Checkout 金额重算 + Price Version。
    #
    # 只编排既有权威：OrderUpdater.new(order).update（其内部 AdjustmentsUpdater 重算
    # promo/tax adjusters + shipment/adjustment totals）——不复制任何公式。
    # 落库后按 Order 权威金额列集合计算 price_version（SHA256 摘要）。
    # checkout_expires_at 为空时初始化为 now+quote_window（结算报价开始计时）。
    class Recalculate
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      def call(order:)
        recalculated = order.with_lock do
          PallasTrade::OrderUpdater.new(order).update
          refreshed = order.reload
          # checkout_version：内容/金额变更后自增（正式 Checkout 版本；与 state_lock_version 无关）
          refreshed.update_columns(
            price_version: fingerprint(refreshed),
            checkout_version: refreshed.checkout_version + 1
          )
          if refreshed.checkout_expires_at.nil?
            refreshed.update_columns(checkout_expires_at: Time.current + PallasTrade::OrderCheckout::Policies.quote_window)
          end
          refreshed.reload
        end

        success(recalculated)
      end

      private

      # 金额输入/结果指纹：仅基于 Order 权威金额列（订单锁价未变则版本稳定）。
      def fingerprint(order)
        parts = [
          order.currency, order.item_total, order.shipment_total, order.adjustment_total,
          order.promo_total, order.included_tax_total, order.additional_tax_total,
          order.total, order.amount_due
        ].map { |v| v.respond_to?(:to_s) ? v.to_s : '' }.join('|')
        Digest::SHA256.hexdigest(parts)[0, 16]
      end
    end
  end
end
