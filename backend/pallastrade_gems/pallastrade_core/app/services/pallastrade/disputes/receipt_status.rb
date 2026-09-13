# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PALLAS-CUSTOM: DSP-P7-10 B3 / FR-009
    # (PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-…)
    #
    # ReceiptStatus —— 证据提交回执的**单向状态机**（provider 回写驱动）。
    #
    # 为什么是"派生"而不是"再建一张表"：
    #   - 回执（`DisputeEvidenceSubmission`）是 **append-only 不可变**的，不允许改它的 `provider_status`；
    #   - 状态机推进的信号**已经存在于系统中**：provider 回写会推进 `Dispute#state`（needs_response →
    #     under_review → won/lost），而"打回补证"会被状态机判为**倒退**并留下 `attention_reason =
    #     invalid_transition`（`Dispute::InvalidTransition` 由 `HandleProviderEvent` 记入 attention）。
    #   - 因此本服务**只读派生**：不写任何行、不发事件、不触网 —— 与报表/扫描器同一纪律。
    #
    # 状态与单调性（每份回执独立，状态只前不后）：
    #   submitted(1) → acknowledged(2) → rejected(3)
    #   - `submitted`：回执已落库，尚无进一步 provider 信号；
    #   - `acknowledged`：provider 已把争议推进到 `under_review` 阶段（= 证据被受理进入复核）；
    #   - `rejected`：provider 把争议**打回** `needs_response`（需补证）→ 触发倒退 → 本地记 `invalid_transition`；
    #   - 信号冲突 / 不完整 → `unknown`（**不猜**），并给出 `reasons[]` 供排障。
    #
    # 单调性依据：`Dispute#state` 的向后倒退会被状态机拒绝，`attention_reason` 亦不被后续流程覆盖
    # （`DeadlineAlertSubscriber` 只在为空时写入）→ 派生值天然不会回退。
    class ReceiptStatus
      prepend PallasTrade::ServiceModule::Base

      SUBMITTED = 'submitted'
      ACKNOWLEDGED = 'acknowledged'
      REJECTED = 'rejected'
      UNKNOWN = 'unknown'

      RANK = { SUBMITTED => 1, ACKNOWLEDGED => 2, REJECTED => 3 }.freeze
      REVIEW_STATES = %w[under_review submitted].freeze
      REJECT_SIGNAL_REASONS = %w[invalid_transition].freeze

      # @param dispute [PallasTrade::Dispute]
      # @param submission [PallasTrade::DisputeEvidenceSubmission, nil] 指定回执（默认取最近一次证据提交回执）
      # @return [PallasTrade::ServiceModule::Result] success({ state:, rank:, receipt_id:, emitted_at:,
      #   provider_status_at_submission:, dispute_state:, previous_state:, reasons: [] })
      def call(dispute:, submission: nil)
        return success(none('dispute_missing')) if dispute.nil?

        receipt = submission || latest_evidence_receipt(dispute)
        return success(none('no_receipt')) if receipt.nil?

        previous = prior_receipt(dispute, receipt)
        derived = derive(dispute, receipt, previous)

        success(
          state: derived[:state],
          rank: RANK[derived[:state]],
          receipt_id: receipt.respond_to?(:prefixed_id) ? receipt.prefixed_id : receipt.id,
          emitted_at: receipt.created_at,
          provider_status_at_submission: receipt.provider_status,
          dispute_state: dispute.state,
          previous_state: previous && (previous.respond_to?(:prefixed_id) ? previous.prefixed_id : previous.id),
          late: receipt.late == true,
          reasons: derived[:reasons]
        )
      end

      private

      def none(reason)
        {
          state: nil, rank: nil, receipt_id: nil, emitted_at: nil,
          provider_status_at_submission: nil, dispute_state: nil, previous_state: nil,
          late: nil, reasons: [reason]
        }
      end

      def latest_evidence_receipt(dispute)
        PallasTrade::DisputeEvidenceSubmission.for_dispute(dispute)
                                              .by_kind('evidence_submitted')
                                              .recent_first.first
      end

      def prior_receipt(dispute, receipt)
        PallasTrade::DisputeEvidenceSubmission.for_dispute(dispute)
                                              .by_kind('evidence_submitted')
                                              .where('created_at < ?', receipt.created_at)
                                              .recent_first.first
      end

      # 单向派生：由"观测到的 provider 信号"推出当前状态，信号不足即 unknown（不猜）
      def derive(dispute, receipt, previous)
        if rejected_signal?(dispute)
          return { state: REJECTED, reasons: ['provider_sent_dispute_back_for_evidence', 'invalid_transition_recorded'] }
        end

        return { state: UNKNOWN, reasons: ['conflicting_signals'] } if conflicting?(dispute, receipt)

        if acknowledged_signal?(dispute, receipt, previous)
          return { state: ACKNOWLEDGED, reasons: ['dispute_reached_under_review'] }
        end

        { state: SUBMITTED, reasons: ['awaiting_provider_writeback'] }
      end

      # 打回补证：本地把 provider 的倒退记为 invalid_transition，且当前 provider 状态回到 needs_response
      def rejected_signal?(dispute)
        return false unless REJECT_SIGNAL_REASONS.include?(dispute.attention_reason.to_s)

        normalized_provider_status(dispute) == 'needs_response'
      end

      # 冲突：既出现打回信号，又已推进到复核之后（例如人为手动改了 attention/状态）→ 不猜
      def conflicting?(dispute, receipt)
        return false unless REJECT_SIGNAL_REASONS.include?(dispute.attention_reason.to_s)

        REVIEW_STATES.include?(dispute.state.to_s) && receipt.provider_status.to_s == 'under_review'
      end

      def acknowledged_signal?(dispute, receipt, previous)
        return true if REVIEW_STATES.include?(dispute.state.to_s)

        # 回执提交时 provider 即回 `under_review`，或该回执之后又出现过新的回执（说明前一份已被处理）
        receipt.provider_status.to_s == 'under_review' || previous.present?
      end

      # provider 归一化状态（复用写入侧同一口径：private_metadata['provider_status']）
      def normalized_provider_status(dispute)
        metadata = dispute.respond_to?(:private_metadata) ? dispute.private_metadata : nil
        return nil unless metadata.is_a?(Hash)

        raw = metadata['provider_status'].presence
        return nil if raw.nil?

        ProviderPayload::STATE_BY_PROVIDER_STATUS[raw.to_s] || raw.to_s
      rescue StandardError
        nil
      end
    end
  end
end
