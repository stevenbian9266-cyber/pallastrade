# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PALLAS-CUSTOM: DSP-P7-10 B1
    # (PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-…)
    #
    # PreSubmitCheck —— 争议证据**提交前**完整性/合规校验（FR-003）。
    #
    # 与既有能力的边界：
    #   - **复用** `EvidenceCatalog`（provider 专属字段/类型/大小规则的**唯一权威**），本服务不复制字段规则；
    #   - 本服务只补足**编排层**判定：provider 是否支持、必填项是否齐全、是否已逾期（含二次确认）、
    #     以及给控制台的**修复建议**（fix_hints）；
    #   - **零写**：不建回执、不写审计、不发事件、不改 `Dispute#state`、不触网（与 `SubmitEvidence` 的
    #     `validate` 前置段完全同构，但不产生任何副作用），可被控制台安全地反复调用。
    class PreSubmitCheck
      prepend PallasTrade::ServiceModule::Base

      TERMINAL_STATES = %w[accepted won lost expired closed].freeze
      LATE_CONFIRMATION_CODE = 'late_submission_requires_confirmation'
      REQUIRED_PREFIX = 'evidence_missing_required'

      # @param dispute [PallasTrade::Dispute]
      # @param evidence [Hash] 与 SubmitEvidence 相同的载荷（文本/文件）
      # @param accept_late [Boolean] 调用方是否已获得逾期二次确认
      # @return [PallasTrade::ServiceModule::Result] success({ ok:, supported:, blocking:, warnings:,
      #   missing_required:, provided_keys:, unknown_keys:, fix_hints:, late:, evidence_due_at:, digest: })
      def call(dispute:, evidence: {}, accept_late: false)
        return success(empty_report.merge(blocking: ['dispute_not_found'])) if dispute.nil?

        dispute = PallasTrade::Dispute.find_by(id: dispute.id)
        return success(empty_report.merge(blocking: ['dispute_not_found'])) if dispute.nil?

        return success(empty_report.merge(blocking: ['dispute_terminal'])) if TERMINAL_STATES.include?(dispute.state.to_s)

        payment_method = dispute.payment&.payment_method
        return success(empty_report.merge(blocking: ['payment_method_missing'])) if payment_method.nil?

        catalog = EvidenceCatalog.new(payment_method: payment_method)
        return success(empty_report.merge(blocking: ['evidence_submission_unsupported'])) unless catalog.supported?

        validation = catalog.validate(evidence)
        provided = (evidence || {}).transform_keys(&:to_s)
        missing_required = catalog.entries.select(&:required).map(&:key) -
                           (validation[:text].keys + validation[:files].keys)
        unknown_keys = provided.keys - catalog.entries.map(&:key)
        late = late_submission?(dispute)

        blocking = []
        blocking.concat(validation[:errors])
        blocking.concat(missing_required.map { |key| "#{REQUIRED_PREFIX}:#{key}" })
        blocking << LATE_CONFIRMATION_CODE if late && !accept_late

        warnings = []
        warnings << 'evidence_deadline_passed' if late && accept_late
        warnings.concat(unknown_keys.map { |key| "evidence_unused_key:#{key}" })

        success({
                  ok: blocking.empty?,
                  supported: true,
                  blocking: blocking,
                  warnings: warnings,
                  missing_required: missing_required,
                  provided_keys: (validation[:text].keys + validation[:files].keys).sort,
                  unknown_keys: unknown_keys,
                  fix_hints: fix_hints(blocking + warnings, missing_required),
                  late: late,
                  evidence_due_at: evidence_due_at(dispute),
                  digest: digest_for(validation)
                })
      end

      private

      def empty_report
        {
          ok: false, supported: false, blocking: [], warnings: [], missing_required: [],
          provided_keys: [], unknown_keys: [], fix_hints: {}, late: false, evidence_due_at: nil, digest: nil
        }
      end

      def late_submission?(dispute)
        due = evidence_due_at(dispute)
        due.present? && Time.current > due
      end

      def evidence_due_at(dispute)
        dispute.respond_to?(:evidence_due_at) ? dispute.evidence_due_at : nil
      end

      def digest_for(validation)
        PallasTrade::DisputeEvidenceSubmission.digest_for(
          text: validation[:text], files: validation[:files].keys.sort
        )
      end

      # 修复建议：code → 建议键（控制台按 i18n 呈现；**不**生成任何内容）
      def fix_hints(codes, missing_required)
        codes.each_with_object({}) do |code, acc|
          base = code.to_s.split(':').first
          acc[code] = case base
                      when 'evidence_empty' then 'fill_at_least_one_field'
                      when 'evidence_too_long' then 'shorten_text'
                      when 'evidence_file_too_large' then 'compress_or_resize_file'
                      when 'evidence_file_type_not_allowed' then 'convert_to_supported_file_type'
                      when 'evidence_not_file', 'evidence_not_text' then 'check_field_type'
                      when 'unknown_evidence_key' then 'remove_unknown_field'
                      when REQUIRED_PREFIX then 'fill_required_field'
                      when LATE_CONFIRMATION_CODE then 'confirm_late_submission'
                      when 'evidence_deadline_passed' then 'expedite_submission'
                      else 'review_payload'
                      end
        end.merge(missing_required.to_h { |key| ["#{REQUIRED_PREFIX}:#{key}", 'fill_required_field'] })
      end
    end
  end
end
