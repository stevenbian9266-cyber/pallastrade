# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-5 (PRD-20260912-payments-dsp-p7-5-dispute-deadline-sweep)
#
# Disputes::ScanDeadlines —— 争议证据期限的**只读**扫描（源计划 §44）。
#
# 语义（不猜 + 只提示）：
#   - 只扫「**未终态**（`Dispute.active`）+ **有** `evidence_due_at`」的争议；无截止日不入结果。
#   - 分桶：`overdue`（`due_at < now`）/ `due_soon`（`now <= due_at <= now + window`）——边界相等归 due_soon。
#   - 排序 `evidence_due_at` 升序（最紧急在前，id 次序稳定），`limit` 截断（避免大表全量）。
#   - 每项携带 P7-4 的 `missing_evidence[]`（让提醒可行动）；证据构建失败 → `evidence_unavailable: true`，不阻断扫描。
#
# 只读边界：零写、零 provider I/O（`BuildEvidenceSnapshot` 走默认 `fetch: false` 纯本地路径）。
module PallasTrade
  module Disputes
    class ScanDeadlines
      prepend PallasTrade::ServiceModule::Base

      DEFAULT_WINDOW_HOURS = 72
      DEFAULT_LIMIT = 500

      # @param window_hours [Integer] 临近窗口（小时）；默认 72
      # @param now [Time] 基准时刻（可注入便于测试/复跑）
      # @param limit [Integer] 单次扫描上限
      # @return [PallasTrade::ServiceModule::Result] success(Hash) / failure(nil, message)
      def call(window_hours: DEFAULT_WINDOW_HOURS, now: Time.current, limit: DEFAULT_LIMIT)
        horizon = now + window_hours.to_f.hours

        candidates = PallasTrade::Dispute.active.
                     where.not(evidence_due_at: nil).
                     where(evidence_due_at: ..horizon).
                     order(:evidence_due_at, :id).
                     limit(limit).
                     to_a

        due_soon = []
        overdue = []
        candidates.each do |dispute|
          item = item_for(dispute, now)
          (item[:hours_remaining].negative? ? overdue : due_soon) << item
        end

        success(due_soon: due_soon, overdue: overdue, window_hours: window_hours,
                scanned_at: now, scanned_count: candidates.size)
      end

      private

      def item_for(dispute, now)
        gaps = evidence_gaps_for(dispute)

        {
          dispute_id: dispute.prefixed_id,
          state: dispute.state,
          evidence_due_at: dispute.evidence_due_at,
          hours_remaining: ((dispute.evidence_due_at - now) / 3600.0).round(2),
          payment_id: dispute.payment&.prefixed_id,
          order_id: dispute.order&.prefixed_id,
          missing_evidence: gaps[:missing_evidence],
          evidence_unavailable: gaps[:evidence_unavailable]
        }
      end

      # 证据缺口（P7-4 只读投影）；不可得时如实降级，绝不用空数组假装「无缺口」
      def evidence_gaps_for(dispute)
        result = PallasTrade::Disputes::BuildEvidenceSnapshot.call(dispute: dispute)
        return { missing_evidence: result.value.missing_evidence, evidence_unavailable: false } if result.success?

        { missing_evidence: [], evidence_unavailable: true }
      rescue StandardError
        { missing_evidence: [], evidence_unavailable: true }
      end
    end
  end
end
