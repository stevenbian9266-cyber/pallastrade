# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-6 (PRD-20260908-payments-rev-p6-6-refund-reverse-recovery)
#
# Refunds::RecoverSweeperJob —— 保守的 refund recovery sweeper（sidekiq-cron 周期调度）。
# 设计决策（镜像 Transactions::RecoverSweeperJob）：
#   - requested 且 stale（> requested_hours）且 attempt_count < MAX → enqueue RecoverJob
#     （Recover 会重跑幂等 Execute；attempts 封顶，超出不自动 enqueue）
#   - processing 且 stale（> processing_hours）→ enqueue RecoverJob（Recover 收敛为 ambiguous）
#   - ambiguous / manual_review / failed → 仅计数 + warn（人工介入；不自动重退 REV-INV-04）
# 幂等：enqueue RecoverJob 无副作用；周期重复安全。
module PallasTrade
  module Refunds
    class RecoverSweeperJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      MAX_AUTO_RETRY_ATTEMPTS = PallasTrade::Refunds::Recover::MAX_AUTO_RETRY_ATTEMPTS

      # @param requested_hours [Integer] requested 未执行判定阈值
      # @param processing_hours [Integer] processing 超时判定阈值
      # @param store_id [Integer, nil] 限定单店（默认全店扫描；按 Refund.payment 归属）
      def perform(requested_hours: 1, processing_hours: 6, store_id: nil)
        scope = PallasTrade::Refund.all
        scope = scope.where(id: store_refund_ids(store_id)) if store_id
        sweep(scope, requested_hours.to_i.hours, processing_hours.to_i.hours, store_id: store_id)
      end

      private

      # 单店 refund 归属：payment.order.store 或 payment.payment_combination.store（组合支付）
      def store_refund_ids(store_id)
        single = PallasTrade::Refund.joins(payment: :order)
                                     .where(pallastrade_orders: { store_id: store_id })
                                     .select(:id)
        combined = PallasTrade::Refund.joins(payment: :payment_combination)
                                      .where(pallastrade_payment_combinations: { store_id: store_id })
                                      .select(:id)
        PallasTrade::Refund.where(id: single).or(PallasTrade::Refund.where(id: combined)).select(:id)
      end

      def sweep(scope, requested_threshold, processing_threshold, store_id:)
        now = Time.current

        requested_stale = scope.where(state: 'requested').where(arel_updated_lt(now - requested_threshold)).reorder(:id)
        requested_enqueued = 0
        requested_capped = 0
        requested_stale.find_each do |refund|
          if refund.attempt_count.to_i >= MAX_AUTO_RETRY_ATTEMPTS
            requested_capped += 1
            next
          end
          PallasTrade::Refunds::RecoverJob.perform_later(refund.id)
          requested_enqueued += 1
        end

        processing_stale = scope.where(state: 'processing').where(arel_updated_lt(now - processing_threshold)).reorder(:id)
        processing_enqueued = processing_stale.count
        processing_stale.find_each { |refund| PallasTrade::Refunds::RecoverJob.perform_later(refund.id) }

        ambiguous_count = scope.where(state: 'ambiguous').count
        manual_review_count = scope.where(state: 'manual_review').count
        failed_count = scope.where(state: 'failed').count

        payload = {
          event: 'refunds.recover_sweeper',
          store_id: store_id,
          requested_stale: requested_stale.count,
          requested_enqueued: requested_enqueued,
          requested_capped: requested_capped,
          processing_stale: processing_stale.count,
          processing_enqueued: processing_enqueued,
          ambiguous: ambiguous_count,
          manual_review: manual_review_count,
          failed: failed_count,
          requested_hours: requested_threshold / 3600,
          processing_hours: processing_threshold / 3600
        }
        Rails.logger.info(payload.to_json)

        if requested_capped.positive? || ambiguous_count.positive? || manual_review_count.positive?
          Rails.logger.warn(
            "[REV-P6-6] refunds need human attention (store #{store_id || 'all'}): " \
            "requested_capped=#{requested_capped} ambiguous=#{ambiguous_count} manual_review=#{manual_review_count}"
          )
        end
      end

      def arel_updated_lt(before)
        PallasTrade::Refund.arel_table[:updated_at].lt(before)
      end
    end
  end
end
