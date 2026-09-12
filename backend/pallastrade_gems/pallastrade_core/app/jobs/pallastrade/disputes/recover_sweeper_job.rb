# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-6 (PRD-20260912-payments-dsp-p7-6-dispute-recovery)
#
# Disputes::RecoverSweeperJob —— 争议收敛 sweeper（sidekiq-cron 每日调度）。
#
# 流程：`ScanRecoveryCandidates`（本地预筛，零 provider I/O）→ 逐条 `Disputes::Recover`（fetch 策略见下）
#   → 事件 + 结构化日志 + 摘要。
#
# fetch 策略（有界 provider 只读调用）：
#   - `journal_gap` 候选 → `fetch: false`（**零网络**：账行补记只依赖本地 funds 时间戳）
#   - `attention` / `stale_active` 候选 → `fetch: true`（需要 provider 当前真相才能判断生命周期是否落后）
#
# 边界（源计划 §49/§50 —— 本 job 永不执行）：不重新扣款、不自动退款、不创建 Payment、不改
#   order/inventory/transaction、不改写既有账行；一切写都经 `Disputes::Recover` 的幂等原语。
#   单条异常隔离（rescue + 日志，继续其余）；重复调度安全（收敛动作幂等）。
#
# 调度：`backend/config/sidekiq_schedule.rb` 的 `dispute_recovery_sweep`（每日 01:30，limit 50）。
module PallasTrade
  module Disputes
    class RecoverSweeperJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      # 决策 → 出站事件（仅「有动作」的决策发事件；noop / manual_review_pending / 降级不发）
      REPAIRED_DECISIONS = %w[
        lifecycle_repaired journal_repaired lifecycle_and_journal_repaired
      ].freeze
      EVENT_BY_KIND = {
        'repaired' => 'dispute.recovery_repaired',
        'manual_review' => 'dispute.recovery_manual_review'
      }.freeze

      # @param limit [Integer] 单次收敛上限（同时约束 provider 只读调用次数）
      # @param verify_after_hours [Numeric] 非终态争议再验证阈值
      # @return [Hash] 运行摘要
      def perform(limit: PallasTrade::Disputes::ScanRecoveryCandidates::DEFAULT_LIMIT,
                  verify_after_hours: PallasTrade::Disputes::ScanRecoveryCandidates::DEFAULT_VERIFY_AFTER_HOURS)
        scan = PallasTrade::Disputes::ScanRecoveryCandidates.call(limit: limit, verify_after_hours: verify_after_hours)
        raise "dispute recovery scan failed: #{scan.error}" unless scan.success?

        summary = { scanned: scan.value[:candidates].size, recovered: 0, manual_review: 0, noop: 0,
                    unavailable: 0, journal_entries_posted: 0, failed: 0,
                    limit: limit, verify_after_hours: verify_after_hours,
                    observed_at: scan.value[:observed_at]&.iso8601 }

        scan.value[:candidates].each do |item|
          converge(item, summary)
        rescue StandardError => e
          summary[:failed] += 1
          Rails.logger.error(
            "[Disputes::RecoverSweeperJob] recovery failed for #{item[:dispute_id]}: #{e.class} #{e.message}"
          )
        end

        Rails.logger.info(JSON.generate({ event: 'disputes.recover_sweeper' }.merge(summary)))
        summary
      end

      private

      def converge(item, summary)
        dispute = item[:dispute]
        return if dispute.nil?

        result = PallasTrade::Disputes::Recover.call(dispute: dispute, fetch: fetch?(item))
        if result.success?
          tally(result.value, summary)
        else
          summary[:failed] += 1
          Rails.logger.error("[Disputes::RecoverSweeperJob] recovery failed for #{item[:dispute_id]}: #{result.error}")
        end
      end

      # 账行缺口走纯本地路径（零 provider I/O）；其余需 provider 当前真相
      def fetch?(item)
        item[:selection] != 'journal_gap'
      end

      # 计数口径：`recovered` / `manual_review` / `noop` / `unavailable` 按**决策**归类；
      # `failed` 为「该条处理抛错」（含事件发布失败）——同一条可能既 recovered 又 failed
      # （事实已修、但通知未发出），以便观测告警链路而不掩盖已完成的收敛。
      def tally(value, summary)
        decision = value[:decision]
        kind = kind_for(decision)
        summary[:recovered] += 1 if REPAIRED_DECISIONS.include?(decision)
        summary[:manual_review] += 1 if decision == 'manual_review_flagged'
        summary[:noop] += 1 if %w[noop manual_review_pending].include?(decision)
        summary[:unavailable] += 1 if %w[unavailable unsupported].include?(decision)
        summary[:journal_entries_posted] += value[:actions].count { |a| a['type'] == 'journal_repair' && a['status'] == 'applied' }

        log(value, kind) if kind
      end

      def kind_for(decision)
        return 'repaired' if REPAIRED_DECISIONS.include?(decision)
        return 'manual_review' if decision == 'manual_review_flagged'

        nil
      end

      # 只发布事件 + 结构化日志（payload 无 PII：仅 id / 决策 / 状态 / 动作类型）
      def log(value, kind)
        event_name = EVENT_BY_KIND.fetch(kind)
        payload = { 'id' => value[:dispute_id], 'decision' => value[:decision],
                    'state' => value[:state_after], 'actions' => value[:actions].map { |a| a['type'] } }
        PallasTrade::Events.publish(event_name, payload) if PallasTrade::Events.enabled?

        Rails.logger.info(
          JSON.generate(event: event_name, dispute_id: value[:dispute_id], decision: value[:decision],
                        state_before: value[:state_before], state_after: value[:state_after],
                        attention_reason: value[:attention_reason],
                        actions: value[:actions].map { |a| a.slice('type', 'status', 'reason', 'entry_type') })
        )
      end
    end
  end
end
