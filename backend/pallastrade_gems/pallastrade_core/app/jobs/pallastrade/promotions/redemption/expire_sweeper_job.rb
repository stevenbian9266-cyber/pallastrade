# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3b-redemption-hardening (FR-002)
#
# reserved 行的 TTL 出口（sidekiq-cron 周期调度）。保守策略，镜像
# `StockReservations::ExpireJob`：只释放「无支付证据、无进行中支付窗口」的过期行。
#   * `reserved_until < now`；或 `reserved_until IS NULL` 且 `reserved_at` 早于宽限期
#     （batch3a 未写入 reserved_until 的历史/直接 Commit 场景，宽限避免误放）
#   * 订单已支付/已完成（payment_total > 0 / completed_at / state in paid|complete）
#     或有进行中 PSP 会话/交易 → 跳过（钱可能已在路上）
# 幂等：只处理 state=reserved；逐行 with_lock 后走 Release 服务（发事件）。
module PallasTrade
  module Promotions
    module Redemption
      class ExpireSweeperJob < PallasTrade::BaseJob
        queue_as PallasTrade.queues.default

        # reserved_until 缺失时的兜底宽限窗口（自 reserved_at 起算）。
        DEFAULT_GRACE = 2.hours

        def perform
          scanned = 0
          released = 0

          eligible.find_each(batch_size: 500) do |redemption|
            scanned += 1
            redemption.with_lock do
              next unless redemption.reload.redemption_reserved?

              Release.call(redemption, reason: 'reserved_timeout')
              released += 1
            end
          end

          Rails.logger.info("[promotions.redemptions] expire sweep scanned=#{scanned} released=#{released}")
          released
        end

        private

        def eligible
          PallasTrade::PromotionRedemption.reserved.
            where('reserved_until < ? OR (reserved_until IS NULL AND reserved_at < ?)',
                  Time.current, DEFAULT_GRACE.ago).
            where.not(order_id: guarded_order_ids)
        end

        # 有支付证据的订单不自动过期（钱已承诺给该订单）。
        def guarded_order_ids
          PallasTrade::Order.where(
            'payment_total > 0 OR completed_at IS NOT NULL OR state IN (?)',
            %w[paid complete]
          ).or(
            PallasTrade::Order.where(id: active_payment_order_ids)
          ).select(:id)
        end

        # 进行中支付窗口（active PSP session 或 active transaction）同样受保护。
        def active_payment_order_ids
          session_order_ids = PallasTrade::PaymentSession.active.
                              where.not(order_id: nil).
                              distinct.pluck(:order_id)
          txn_order_ids = PallasTrade::TransactionOrder.where(
            transaction_id: PallasTrade::CommerceTransaction.where(state: %w[created payment_pending]).select(:id)
          ).distinct.pluck(:order_id)

          (session_order_ids + txn_order_ids).uniq
        end
      end
    end
  end
end
