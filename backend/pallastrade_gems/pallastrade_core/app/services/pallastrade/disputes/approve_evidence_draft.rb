# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PALLAS-CUSTOM: DSP-P7-10 B2 / FR-005
    # (PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-…)
    #
    # ApproveEvidenceDraft —— 证据草稿的**双人复核签核**（FR-005）。
    #
    # 定位：**加强**危险操作，而非替换它。`Disputes::SubmitEvidence` 仍是唯一提交口（permission +
    # confirmation + audit 三件套不变）；本服务只产出"这份草稿是否已获第二人签核"的**不可变凭证**。
    #
    # 铁律：
    #   - 签核对象是**载荷摘要**（与提交幂等基准同算法）→ 草稿被改，原签核自动失效；
    #   - `requested_by` 与签发人相同时拒绝（`approval_requires_different_operator`）——"自己批自己"不算复核；
    #   - **零 provider I/O、零资金副作用**：不提交、不建回执、不改 `Dispute#state`；
    #   - 幂等：同一 (dispute, digest, decision, actor) 重复签核 → 返回既有记录。
    class ApproveEvidenceDraft
      prepend PallasTrade::ServiceModule::Base

      # @param dispute [PallasTrade::Dispute]
      # @param actor [String, Hash] 签发人（`{ type:, id:, label: }` 或字符串）
      # @param payload_digest [String, nil] 直接给出摘要（须与提交方一致）
      # @param evidence [Hash, nil] 或给出草稿载荷（由 PreSubmitCheck 计算摘要，保证同算法）
      # @param decision [String] approved / rejected
      # @param note [String, nil] 复核意见
      # @param requested_by [String, nil] 起草人（与签发人相同则拒绝）
      # @return [PallasTrade::ServiceModule::Result] success({ approval:, idempotent: }) / failure(code)
      def call(dispute:, actor: 'admin', payload_digest: nil, evidence: nil, decision: 'approved',
               note: nil, requested_by: nil)
        return failure(nil, 'dispute_not_found') if dispute.nil?

        dispute = PallasTrade::Dispute.find_by(id: dispute.id)
        return failure(nil, 'dispute_not_found') if dispute.nil?
        return failure(nil, 'dispute_terminal') if PallasTrade::Dispute::TERMINAL_STATES.include?(dispute.state.to_s)
        return failure(nil, 'invalid_decision') unless PallasTrade::DisputeEvidenceApproval::DECISIONS.include?(decision.to_s)

        payment_method = dispute.payment&.payment_method
        return failure(nil, 'payment_method_missing') if payment_method.nil?

        catalog = EvidenceCatalog.new(payment_method: payment_method)
        return failure(nil, 'evidence_submission_unsupported') unless catalog.supported?

        digest = resolve_digest(dispute, payload_digest, evidence)
        return failure(nil, 'payload_digest_missing') if digest.blank?

        label = actor_label(actor)
        return failure(nil, 'approval_requires_different_operator') if same_operator?(requested_by, label)

        key = actor_key(actor, label)
        existing = PallasTrade::DisputeEvidenceApproval.for_dispute(dispute).find_by(
          payload_digest: digest, decision: decision.to_s, actor_id: key
        )
        return success({ approval: existing, idempotent: true }) if existing

        approval = PallasTrade::DisputeEvidenceApproval.create!(
          dispute: dispute,
          payload_digest: digest,
          decision: decision.to_s,
          actor_type: actor_field(actor, :type),
          actor_id: key,
          actor_label: label,
          requested_by: requested_by.presence&.to_s,
          note: note.presence&.to_s
        )

        audit(dispute, approval, actor)
        success({ approval: approval, idempotent: false })
      end

      private

      # 摘要来源：显式给出优先；否则对草稿跑**同一个** PreSubmitCheck（与提交幂等基准同算法）。
      # 空草稿**不产生签核**（空载荷同样有摘要，但批一份空草稿没有意义）。
      def resolve_digest(dispute, payload_digest, evidence)
        return payload_digest.to_s if payload_digest.present?

        report = PreSubmitCheck.call(dispute: dispute, evidence: evidence || {})
        return nil unless report.success?
        return nil if Array(report.value[:blocking]).include?('evidence_empty') && report.value[:provided_keys].blank?

        report.value[:digest]
      end

      def same_operator?(requested_by, label)
        requested_by.present? && label.present? && requested_by.to_s.strip == label.to_s.strip
      end

      # 唯一键的兜底：Hash actor 用 id，字符串 actor 用其本身 —— 保证"同一人"可被判重
      def actor_key(actor, label)
        actor_field(actor, :id).presence || label.presence || 'admin'
      end

      def actor_field(actor, key)
        return actor[key].to_s if actor.is_a?(Hash) && actor.key?(key)
        return actor[key.to_s].to_s if actor.is_a?(Hash) && actor.key?(key.to_s)
        return nil if key != :label

        actor.to_s
      end

      def actor_label(actor)
        actor_field(actor, :label)
      end

      def audit(dispute, approval, actor)
        PallasTrade::Audit.record(
          action: approval.approved? ? 'dispute_evidence_draft_approved' : 'dispute_evidence_draft_rejected',
          actor: actor,
          resource: dispute,
          after: {
            approval: approval.prefixed_id,
            payload_digest: approval.payload_digest.to_s[0, 12],
            decision: approval.decision,
            requested_by: approval.requested_by
          }
        )
      end
    end
  end
end
