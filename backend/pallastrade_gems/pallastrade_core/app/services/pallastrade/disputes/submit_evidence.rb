# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PALLAS-CUSTOM: DSP-P7-8 (PRD-20260913-payments-dsp-p7-8)
    #
    # SubmitEvidence —— 向 provider **提交争议证据**（源计划 §67 的危险操作之一）。
    #
    # 三件套（源计划 §67 强制）：
    #   - permission：控制台侧 `can?(:update, PallasTrade::Dispute)`（本服务不重复判权，由调用方保证）；
    #   - confirmation：控制台 `turbo_confirm`（逾期提交额外要求 `accept_late: true`）；
    #   - audit：成功 → `dispute_evidence_submitted`；失败 → `dispute_evidence_submit_failed`（**都**留痕）。
    #
    # 铁律：
    #   - **零资金副作用**：不建/改 Payment / Refund / FinancialLedgerEntry / Order / Inventory /
    #     CommerceTransaction；资金结果仍由 provider webhook 驱动 P7-3 入账与 P7-6 收敛；
    #   - **不改 `Dispute#state`**（状态机由 webhook / 收敛推进；本服务只写回执 + 审计 + 事件）；
    #   - **幂等**：同一 `(dispute, payload_digest)` 重复提交 → 返回既有回执，**不**再次调用 provider；
    #   - **失败不落回执**：provider 抛错时返回 failure 并只写审计（避免"半成品回执"污染幂等基准）。
    class SubmitEvidence
      prepend PallasTrade::ServiceModule::Base

      TERMINAL_STATES = %w[accepted won lost expired closed].freeze

      # @param dispute [PallasTrade::Dispute]
      # @param evidence [Hash] 证据键 → 文本值 / 文件对象（UploadedFile 或 stream）
      # @param actor [String, Hash] 操作者（`{ type:, id:, label: }` 或字符串）
      # @param accept_late [Boolean] 逾期提交是否已经过二次确认
      # @return [PallasTrade::ServiceModule::Result] success({ submission:, idempotent:, late:, provider_status: })
      def call(dispute:, evidence:, actor: 'admin', accept_late: false)
        return failure(nil, 'dispute_not_found') if dispute.nil?

        dispute = PallasTrade::Dispute.find_by(id: dispute.id)
        return failure(nil, 'dispute_not_found') if dispute.nil?
        return failure(nil, 'dispute_terminal') if TERMINAL_STATES.include?(dispute.state.to_s)

        payment_method = dispute.payment&.payment_method
        return failure(nil, 'payment_method_missing') if payment_method.nil?

        catalog = EvidenceCatalog.new(payment_method: payment_method)
        return failure(nil, 'evidence_submission_unsupported') unless catalog.supported?

        validation = catalog.validate(evidence)
        return failure(nil, validation[:errors].join(',')) unless validation[:ok]

        late = late_submission?(dispute)
        return failure(nil, 'late_submission_not_confirmed') if late && !accept_late

        digest = payload_digest(validation)
        existing = find_existing(dispute, digest)
        return success({ submission: existing, idempotent: true, late: existing.late, provider_status: existing.provider_status }) if existing

        receipt = write_to_provider(dispute, payment_method, validation, actor)
        return failure(nil, receipt[:error]) if receipt[:error]

        submission = persist_receipt(dispute, digest, receipt, validation, late, actor)
        attach_files(submission, validation[:files])
        audit_success(dispute, actor, submission)
        publish_event(dispute, submission)

        success({
                  submission: submission,
                  idempotent: false,
                  late: late,
                  provider_status: submission.provider_status
                })
      end

      private

      def late_submission?(dispute)
        dispute.respond_to?(:evidence_due_at) && dispute.evidence_due_at.present? &&
          Time.current > dispute.evidence_due_at
      end

      def payload_digest(validation)
        PallasTrade::DisputeEvidenceSubmission.digest_for(
          text: validation[:text],
          files: validation[:files].keys.sort
        )
      end

      def find_existing(dispute, digest)
        PallasTrade::DisputeEvidenceSubmission.find_by(
          dispute_id: dispute.id, kind: 'evidence_submitted', payload_digest: digest
        )
      end

      # provider 写：唯一对外动作。抛错 → 审计 + failure（**不**落回执）。
      def write_to_provider(dispute, payment_method, validation, actor)
        evidence = validation[:text].merge(validation[:files])
        receipt = payment_method.submit_dispute_evidence(dispute: dispute, evidence: evidence)
        { provider_reference: receipt[:provider_reference], status: receipt[:status], metadata: receipt[:metadata] || {} }
      rescue StandardError => e
        PallasTrade::Audit.record(
          action: 'dispute_evidence_submit_failed',
          actor: actor,
          resource: dispute,
          after: { error: e.class.name, message: e.message.to_s[0, 500] }
        )
        { error: "provider_error:#{e.class.name}" }
      end

      def persist_receipt(dispute, digest, receipt, validation, late, actor)
        PallasTrade::DisputeEvidenceSubmission.create!(
          dispute: dispute,
          kind: 'evidence_submitted',
          payload_digest: digest,
          provider_reference: receipt[:provider_reference],
          provider_status: receipt[:status],
          actor_type: actor_field(actor, :type),
          actor_id: actor_field(actor, :id),
          actor_label: actor_field(actor, :label),
          late: late,
          response_metadata: receipt[:metadata].merge('evidence_keys' => validation[:text].keys.sort + validation[:files].keys.sort)
        )
      end

      # 文件留存：附件挂在**回执**上（审计留存），provider 侧引用写进 response_metadata
      def attach_files(submission, files)
        return if files.blank?

        files.each_value do |file|
          io = file.respond_to?(:read) ? file : nil
          next if io.nil?

          submission.evidence_files.attach(
            io: io,
            filename: file_name(file),
            content_type: file.respond_to?(:content_type) ? file.content_type : 'application/octet-stream'
          )
        end
      rescue StandardError
        nil # 留存失败不影响已成功的 provider 写（回执本身已落库）
      end

      def file_name(file)
        if file.respond_to?(:original_filename) then file.original_filename.to_s
        elsif file.respond_to?(:filename) then file.filename.to_s
        else 'evidence'
        end
      end

      def audit_success(dispute, actor, submission)
        PallasTrade::Audit.record(
          action: 'dispute_evidence_submitted',
          actor: actor,
          resource: dispute,
          after: {
            submission: submission.prefixed_id,
            provider_reference: submission.provider_reference,
            provider_status: submission.provider_status,
            late: submission.late,
            evidence_keys: submission.response_metadata['evidence_keys']
          }
        )
      end

      def publish_event(dispute, submission)
        dispute.publish_event(
          'dispute.evidence_submitted',
          dispute_id: dispute.prefixed_id,
          submission_id: submission.prefixed_id,
          provider_status: submission.provider_status,
          late: submission.late,
          evidence_keys: submission.response_metadata['evidence_keys']
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
