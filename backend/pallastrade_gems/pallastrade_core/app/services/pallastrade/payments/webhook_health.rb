# frozen_string_literal: true

module PallasTrade
  module Payments
    # PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance 切片2）——
    # Webhook 健康聚合（业务方案 §69「端点健康 / 告警」的只读数据面）。
    #
    # 两部分（全部为**只读聚合**，零 provider 调用、零 payload 加载）：
    #   inbound  —— 入站 provider 事件（`PaymentWebhookEvent`）：近 24h 各状态计数、
    #               失败率、平均处理耗时（processed_at - received_at）、积压（received+processing）、
    #               最近失败时间。
    #   outbound —— 出站商户投递（`WebhookDelivery`）：近 24h 成功/失败计数、成功率、
    #               积压（success IS NULL）、最近失败时间。
    #
    # 口径说明：失败率 = failed / (processed + failed)（不含未决）；空库返回零值而不报错。
    module WebhookHealth
      WINDOW = 24.hours

      module_function

      # @param now [Time]
      # @return [Hash] { window:, inbound: {...}, outbound: {...} }
      def call(now: Time.current)
        since = now - WINDOW

        {
          window: WINDOW.inspect,
          inbound: inbound(now: now, since: since),
          outbound: outbound(now: now, since: since)
        }
      end

      # @return [Hash]
      def inbound(now: Time.current, since: (now - WINDOW))
        events = PallasTrade::PaymentWebhookEvent.where(received_at: since..now)
        counts = events.group(:status).count
        processed = counts.fetch('processed', 0)
        failed = counts.fetch('failed', 0)
        settled = processed + failed

        {
          total: events.count,
          by_status: counts,
          backlog: counts.fetch('received', 0) + counts.fetch('processing', 0),
          quarantined: counts.fetch('quarantined', 0),
          failure_rate: settled.zero? ? 0.0 : (failed.to_f / settled).round(4),
          avg_processing_seconds: average_processing_seconds(events),
          last_failure_at: events.failed.maximum(:processed_at)
        }
      end

      # @return [Hash]
      def outbound(now: Time.current, since: (now - WINDOW))
        deliveries = PallasTrade::WebhookDelivery.where(created_at: since..now)
        succeeded = deliveries.where(success: true).count
        failed = deliveries.where(success: false).count
        settled = succeeded + failed

        {
          total: deliveries.count,
          succeeded: succeeded,
          failed: failed,
          backlog: deliveries.where(success: nil).count,
          success_rate: settled.zero? ? 0.0 : (succeeded.to_f / settled).round(4),
          last_failure_at: deliveries.where(success: false).maximum(:delivered_at)
        }
      end

      # 平均处理耗时（秒，3 位小数）：仅统计已有 processed_at 的事件。
      # @return [Float, nil]
      def average_processing_seconds(events)
        rows = events.where.not(processed_at: nil).where.not(received_at: nil)
        count = rows.count
        return nil if count.zero?

        # 单次 SQL 聚合（避免把 payload 拉进内存）。
        total = rows.sum('EXTRACT(EPOCH FROM (processed_at - received_at))')
        (total.to_f / count).round(3)
      end
    end
  end
end
