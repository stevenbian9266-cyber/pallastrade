# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-10 B2 / FR-007
# (PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-…)
#
# DeadlineAlertSubscriber —— 争议证据期限的**提醒与升级**（FR-007）。
#
# 事件源：`Disputes::DeadlineSweeperJob` 逐条发布的 `dispute.evidence_due_soon` / `dispute.evidence_overdue`。
#   扫描器（`ScanDeadlines` / sweeper）保持**只读**；把"通知与升级"放在订阅者，职责分离。
#
# 语义（**提醒，不代替人决策；零自动化**）：
#   - `due_soon`：只留痕（审计 + 指标），**不改任何状态** —— 提醒运营尽快准备；
#   - `overdue` ：在**不覆盖既有标记**的前提下把争议标为需要人工关注
#     （`attention_reason = 'evidence_overdue'`）—— 该标记会出现在控制台与运营报表的 needs_attention 指标里；
#   - 绝不自动提交证据 / 自动接受争议 / 自动退款 / 改库存订单（§71 禁区）；
#   - 终态争议、找不到的争议 → no-op；异常 rescue 记日志（绝不阻断 sweeper 或争议落库）。
module PallasTrade
  module Disputes
    class DeadlineAlertSubscriber < PallasTrade::Subscriber
      subscribes_to 'dispute.evidence_due_soon', 'dispute.evidence_overdue', 'dispute.evidence_deadline_tier'

      OVERDUE_REASON = 'evidence_overdue'
      # D14 切片2：`dispute.evidence_deadline_tier` 携带 `tier` 字段（t3 / t1 / overdue），
      # 映射为 `tier_*` kind 以便与既有两类事件的留痕区分。
      KIND_BY_EVENT = {
        'dispute.evidence_due_soon' => 'due_soon',
        'dispute.evidence_overdue' => 'overdue',
        'dispute.evidence_deadline_tier' => 'tier'
      }.freeze

      def handle(event)
        dispute = find_dispute(event.payload)
        return if dispute.nil?
        return if PallasTrade::Dispute::TERMINAL_STATES.include?(dispute.state.to_s)

        kind = KIND_BY_EVENT[event.name] || 'unknown'
        escalate(dispute) if overdue_alert?(kind, event.payload)
        record_alert(dispute, kind, event.payload)
      rescue StandardError => e
        Rails.logger.error(
          "[Disputes::DeadlineAlertSubscriber] deadline alert failed for #{event&.name}: #{e.class} #{e.message}"
        )
      end

      private

      # 超期告警（既有 `dispute.evidence_overdue` 或分档事件里的 `overdue` 档）
      def overdue_alert?(kind, payload)
        return true if kind == 'overdue'

        kind == 'tier' && tier_of(payload) == PallasTrade::DisputeDeadlineAlert::OVERDUE_TIER
      end

      def tier_of(payload)
        payload.try(:[], 'tier') || payload.try(:[], :tier)
      end

      # 升级＝打人工关注标记（不覆盖更具体的原因，如 provider_conflict / journal_gap）
      def escalate(dispute)
        return if dispute.attention_reason.present?

        dispute.update!(attention_reason: OVERDUE_REASON)
      end

      def record_alert(dispute, kind, payload)
        tier = payload.try(:[], 'tier') || payload.try(:[], :tier)

        PallasTrade::Audit.record(
          action: tier.present? ? 'dispute_deadline_tier_alerted' : 'dispute_deadline_alerted',
          actor: 'system',
          resource: dispute,
          after: {
            kind: kind,
            tier: tier,
            evidence_due_at: dispute.evidence_due_at&.iso8601,
            hours_remaining: hours_remaining(payload),
            attention_reason: dispute.attention_reason
          }.compact
        )
        PallasTrade::OperationalMetrics.count('dispute.deadline_alert', kind: kind, dispute_id: dispute.prefixed_id)
      rescue StandardError
        nil # 留痕失败不影响提醒语义（与既有订阅者的降级取向一致）
      end

      def hours_remaining(payload)
        payload.try(:[], 'hours_remaining') || payload.try(:[], :hours_remaining)
      end

      # payload id 双模（prefixed `dsp_` / raw integer），对齐 FinancialLedger::DisputeFundsSubscriber
      def find_dispute(payload)
        id = payload.try(:[], 'id') || payload.try(:[], :id)
        return if id.blank?

        if id.to_s.start_with?('dsp_')
          PallasTrade::Dispute.find_by_param(id)
        else
          PallasTrade::Dispute.find_by(id: id)
        end
      end
    end
  end
end
