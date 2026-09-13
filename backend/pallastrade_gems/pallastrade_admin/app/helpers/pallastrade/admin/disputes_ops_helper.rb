# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-7 (PRD-20260913-payments-dsp-p7-7-admin-disputes-console)
#
# Dispute Ops 展示 helper —— 状态 / 标记 / 裁决 的 badge 映射集中在此（视图不写业务判断）。
module PallasTrade
  module Admin
    module DisputesOpsHelper
      # 域内 10 态 → badge（终态收敛=绿/灰，人工态=橙，进行中=蓝）
      DISPUTE_STATE_BADGE = {
        'opened' => 'badge-info',
        'needs_response' => 'badge-warning',
        'submitted' => 'badge-info',
        'under_review' => 'badge-info',
        'won' => 'badge-success',
        'lost' => 'badge-danger',
        'accepted' => 'badge-danger',
        'expired' => 'badge-inactive',
        'closed' => 'badge-inactive',
        'manual_review' => 'badge-warning'
      }.freeze

      # 人工标记原因（P7-1 入口 / P7-6 收敛 / P7-7 后台）→ badge
      ATTENTION_BADGE = {
        'unlinked_payment' => 'badge-danger',
        'non_positive_amount' => 'badge-danger',
        'invalid_transition' => 'badge-warning',
        'provider_conflict' => 'badge-danger',
        'journal_gap' => 'badge-warning',
        'funds_evidence_missing' => 'badge-warning',
        'operator_review' => 'badge-info'
      }.freeze

      # P7-2 裁决 → badge
      RESOLUTION_BADGE = {
        'aligned' => 'badge-success',
        'stale_local' => 'badge-warning',
        'stale_provider' => 'badge-warning',
        'conflict' => 'badge-danger',
        'unknown' => 'badge-inactive',
        'unsupported' => 'badge-inactive',
        'unavailable' => 'badge-inactive',
        'not_applicable' => 'badge-inactive'
      }.freeze

      # 列表/详情共用的 state 徽章
      def dispute_state_badge(dispute)
        css = DISPUTE_STATE_BADGE.fetch(dispute.state, 'badge-light')
        content_tag(:span, dispute.state.humanize, class: "badge #{css}")
      end

      # 列表/详情共用的 attention 徽章（无标记返回 —）
      def dispute_attention_badge(dispute)
        reason = dispute.attention_reason
        return content_tag(:span, '—', class: 'text-gray-400') if reason.blank?

        css = ATTENTION_BADGE.fetch(reason, 'badge-light')
        content_tag(:span, reason.humanize, class: "badge #{css}")
      end

      # 详情页裁决徽章
      def dispute_resolution_badge(resolution)
        return content_tag(:span, '—', class: 'text-gray-400') if resolution.blank?

        css = RESOLUTION_BADGE.fetch(resolution.to_s, 'badge-light')
        content_tag(:span, resolution.to_s.humanize, class: "badge #{css}")
      end

      # 详情页「收敛状态」文案：最近一次收敛（P7-6 审计）与是否有未决人工标记
      def dispute_recovery_hint(dispute, recovery)
        return 'Awaiting first convergence run.' if recovery.blank? && dispute.attention_reason.blank?
        return "Marked for human review: #{dispute.attention_reason.humanize}." if recovery.blank?

        "#{recovery['decision']} at #{recovery['at']} (#{recovery['from']} → #{recovery['to']})"
      end
    end
  end
end
