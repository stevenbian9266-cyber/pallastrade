# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-5 (PRD-20260912-payments-dsp-p7-5-dispute-deadline-sweep)
#
# Disputes::DeadlineSweeperJob —— 争议证据期限扫描 + 告警（sidekiq-cron 每日调度）。
#
# 边界（源计划 §45 —— 只提示，不替商户决策）：
#   - **只**发布事件（`dispute.evidence_due_soon` / `dispute.evidence_overdue`）+ 结构化 JSON 日志（供告警/指标）；
#   - **绝不**：提交证据、接受/关闭争议、退款、改任何 dispute/payment/order 状态、调用 provider 写接口。
#   - 单条异常隔离（rescue + 日志，继续其余）；整体摘要返回，便于观测。
#
# 幂等/可重跑：扫描为纯只读（同 now 同结果）；重复调度不产生副作用（事件重复由下游决定去重）。
# 调度：`backend/config/sidekiq_schedule.rb` 的 `dispute_deadline_sweep`（每日 01:00，window 72h）。
module PallasTrade
  module Disputes
    class DeadlineSweeperJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      EVENT_BY_BUCKET = {
        'overdue' => 'dispute.evidence_overdue',
        'due_soon' => 'dispute.evidence_due_soon'
      }.freeze

      # @param window_hours [Integer] 临近窗口（小时）；默认 72
      # @return [Hash] 运行摘要 { published:, failed:, overdue:, due_soon:, window_hours:, scanned_at: }
      def perform(window_hours: PallasTrade::Disputes::ScanDeadlines::DEFAULT_WINDOW_HOURS)
        result = PallasTrade::Disputes::ScanDeadlines.call(window_hours: window_hours)
        raise "dispute deadline scan failed: #{result.error}" unless result.success?

        value = result.value
        published = 0
        failed = 0

        [{ 'overdue' => value[:overdue] }, { 'due_soon' => value[:due_soon] }].each do |bucket_hash|
          bucket, items = bucket_hash.first
          items.each do |item|
            alert(bucket, item)
            published += 1
          rescue StandardError => e
            failed += 1
            Rails.logger.error(
              "[Disputes::DeadlineSweeperJob] alert failed for #{item[:dispute_id]}: #{e.class} #{e.message}"
            )
          end
        end

        summary = { published: published, failed: failed, overdue: value[:overdue].size,
                    due_soon: value[:due_soon].size, window_hours: value[:window_hours],
                    scanned_at: value[:scanned_at]&.iso8601 }
        Rails.logger.info(JSON.generate({ event: 'disputes.deadline_sweeper' }.merge(summary)))
        summary
      end

      private

      # 只发布事件 + 记账日志：不触碰任何业务状态
      def alert(bucket, item)
        payload = {
          'id' => item[:dispute_id],
          'state' => item[:state],
          'due_at' => item[:evidence_due_at]&.iso8601,
          'hours_remaining' => item[:hours_remaining],
          'missing_evidence' => item[:missing_evidence]
        }
        event_name = EVENT_BY_BUCKET.fetch(bucket)
        PallasTrade::Events.publish(event_name, payload) if PallasTrade::Events.enabled?

        Rails.logger.info(
          JSON.generate(event: event_name, dispute_id: item[:dispute_id], state: item[:state],
                        due_at: item[:evidence_due_at]&.iso8601, hours_remaining: item[:hours_remaining],
                        missing_evidence: item[:missing_evidence])
        )
      end
    end
  end
end
