# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8a (PRD-20260908-payments-rev-p6-8a-refund-admin-ops; 源 P6 §63)
module PallasTrade
  module Admin
    module RefundsOpsHelper
      REFUND_STATE_BADGE = {
        'requested' => 'badge-info',
        'processing' => 'badge-info',
        'succeeded' => 'badge-success',
        'failed' => 'badge-danger',
        'ambiguous' => 'badge-warning',
        'manual_review' => 'badge-warning',
        'canceled' => 'badge-inactive'
      }.freeze

      # Refund state → badge（REV-P6-1 七态；列表/详情共用）
      def refund_state_badge(refund)
        css = REFUND_STATE_BADGE.fetch(refund.state, 'badge-light')
        content_tag(:span, refund.state.humanize, class: "badge #{css}")
      end

      # Recovery 卡文案（只读派生，镜像 Refunds::Recover 语义：requested>1h & attempts<5 自动重跑；
      # processing>6h → ambiguous；ambiguous/manual 人工裁决；attempt 达 5 转人工）
      def refund_recovery_hint(refund)
        case refund.state
        when 'requested'
          if refund.attempt_count >= PallasTrade::Refunds::Recover::MAX_AUTO_RETRY_ATTEMPTS
            'Auto-retry attempts exhausted — manual action required.'
          else
            'Requested — auto-retry may re-run once stale (>1h).'
          end
        when 'processing'
          'Processing — will be marked ambiguous after 6h (never auto re-refunded).'
        when 'ambiguous'
          'Ambiguous — deterministic resolution / manual review required (no auto re-refund).'
        when 'manual_review'
          'Manual review — awaiting operator decision.'
        when 'failed'
          'Failed — retry via manual review (REV-P6-8b).'
        else
          'Terminal state.'
        end
      end
    end
  end
end
