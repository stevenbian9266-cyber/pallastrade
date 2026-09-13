# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PALLAS-CUSTOM: DSP-P7-8 (PRD-20260913-payments-dsp-p7-8)
    #
    # AcceptDispute —— **接受争议**（放弃抗辩；源计划 §67 的危险操作之一，**不可逆**）。
    #
    # 语义：
    #   - provider 侧 = 关闭争议（Stripe `Dispute#close`）；本地只治理**回执 + 审计 + 事件**；
    #   - **不写本地状态机**：`Dispute#state` 仍由 provider webhook（P7-1）与收敛（P7-6）推进 ——
    #     避免"控制台直接改状态"绕过事实裁决；
    #   - **零资金副作用**：扣款/入账由 webhook → P7-3 账本链路完成，本服务不碰 Payment/Refund/Ledger；
    #   - 三件套：permission（调用方 `can?(:update, Dispute)`）+ confirmation（控制台二次确认，
    #     文案含"不可撤销"）+ audit（成功 `dispute_accepted` / 失败 `dispute_accept_failed`）；
    #   - 幂等：同一 `(dispute, payload_digest)` 重复接受 → 返回既有回执，不重复调用 provider。
    class AcceptDispute
      prepend PallasTrade::ServiceModule::Base

      # 已终态的争议不可再"接受"（除 manual_review 与在途态）
      TERMINAL_STATES = %w[accepted won lost expired closed].freeze

      # @param dispute [PallasTrade::Dispute]
      # @param reason [String] 必填：为什么放弃抗辩（审计可读）
      # @param actor [String, Hash]
      # @return [PallasTrade::ServiceModule::Result] success({ submission:, idempotent:, provider_status: })
      def call(dispute:, reason:, actor: 'admin')
        return failure(nil, 'dispute_not_found') if dispute.nil?

        dispute = PallasTrade::Dispute.find_by(id: dispute.id)
        return failure(nil, 'dispute_not_found') if dispute.nil?
        return failure(nil, 'reason_required') if reason.to_s.strip.empty?
        return failure(nil, 'dispute_terminal') if TERMINAL_STATES.include?(dispute.state.to_s)

        payment_method = dispute.payment&.payment_method
        return failure(nil, 'payment_method_missing') if payment_method.nil?
        return failure(nil, 'accept_unsupported') unless accept_supported?(payment_method)

        digest = PallasTrade::DisputeEvidenceSubmission.digest_for(reason: reason.to_s.strip)
        existing = PallasTrade::DisputeEvidenceSubmission.find_by(
          dispute_id: dispute.id, kind: 'accepted', payload_digest: digest
        )
        return success({ submission: existing, idempotent: true, provider_status: existing.provider_status }) if existing

        receipt = write_to_provider(dispute, payment_method, reason, actor)
        return failure(nil, receipt[:error]) if receipt[:error]

        submission = PallasTrade::DisputeEvidenceSubmission.create!(
          dispute: dispute,
          kind: 'accepted',
          payload_digest: digest,
          provider_reference: receipt[:provider_reference],
          provider_status: receipt[:status],
          actor_type: actor_field(actor, :type),
          actor_id: actor_field(actor, :id),
          actor_label: actor_field(actor, :label),
          accepted_reason: reason.to_s.strip,
          response_metadata: receipt[:metadata]
        )

        audit_success(dispute, actor, submission)
        publish_event(dispute, submission)

        success({ submission: submission, idempotent: false, provider_status: submission.provider_status })
      end

      private

      def accept_supported?(payment_method)
        return false unless payment_method.respond_to?(:accept_dispute)

        # 能力探测沿用类级 owner 检查（零 I/O；同 fetch_dispute_details 范式）
        owner = payment_method.class.instance_method(:accept_dispute).owner
        owner != PallasTrade::PaymentMethod
      rescue NameError
        false
      end

      def write_to_provider(dispute, payment_method, reason, actor)
        receipt = payment_method.accept_dispute(dispute: dispute, reason: reason.to_s.strip)
        { provider_reference: receipt[:provider_reference], status: receipt[:status], metadata: receipt[:metadata] || {} }
      rescue StandardError => e
        PallasTrade::Audit.record(
          action: 'dispute_accept_failed',
          actor: actor,
          resource: dispute,
          after: { error: e.class.name, message: e.message.to_s[0, 500], reason: reason.to_s.strip[0, 200] }
        )
        { error: "provider_error:#{e.class.name}" }
      end

      def audit_success(dispute, actor, submission)
        PallasTrade::Audit.record(
          action: 'dispute_accepted',
          actor: actor,
          resource: dispute,
          after: {
            submission: submission.prefixed_id,
            provider_reference: submission.provider_reference,
            provider_status: submission.provider_status,
            reason: submission.accepted_reason
          }
        )
      end

      def publish_event(dispute, submission)
        dispute.publish_event(
          'dispute.accepted',
          dispute_id: dispute.prefixed_id,
          submission_id: submission.prefixed_id,
          provider_status: submission.provider_status,
          reason: submission.accepted_reason
        )
      end

      def actor_field(actor, key)
        return actor[key].to_s if actor.is_a?(Hash) && actor.key?(key)
        return nil if key != :label

        actor.to_s
      end
    end
  end
end
