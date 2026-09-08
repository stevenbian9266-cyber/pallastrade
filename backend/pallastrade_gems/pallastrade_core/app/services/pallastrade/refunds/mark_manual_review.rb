# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8b (PRD-20260908-payments-rev-p6-8b-refund-manual-review-retry)
#
# Refunds::MarkManualReview —— 人工标记复核（源 REV-P6 §10/§63 Manual Review）。
#   - 仅 processing / ambiguous → enter_manual_review!(code: 'OPERATOR_REVIEW')（非终态侧，表示进入人工裁决；
#     无资金副作用）。复核后的裁决 = Refunds::ManualRetry（同键确定性解决）。
#   - 其余态（requested/failed/succeeded/canceled/manual_review 已处于）→ failure 零副作用。
#   - 幂等/并发：with_lock + reload + 状态守卫（enter_manual_review! 幂等：manual_review 已处则 no-op true）。
module PallasTrade
  module Refunds
    class MarkManualReview
      prepend PallasTrade::ServiceModule::Base

      ELIGIBLE_STATES = %w[processing ambiguous].freeze

      # @param refund [PallasTrade::Refund]
      # @param actor [String, Hash, #id]
      # @return [PallasTrade::ServiceModule::Result]
      def call(refund:, actor: 'admin')
        return failure(nil, 'Refund not found') if refund.nil?

        refund = PallasTrade::Refund.find_by(id: refund.id)
        return failure(nil, 'Refund not found') if refund.nil?

        refund.with_lock do
          refund.reload
          unless refund.state.in?(ELIGIBLE_STATES)
            return failure(refund, "Refund #{refund.prefixed_id} cannot be marked for manual review (state=#{refund.state})")
          end

          refund.enter_manual_review!(code: 'OPERATOR_REVIEW',
                                      message: 'Marked for manual review by operator')
          refund.save!
        end

        PallasTrade::Audit.record(
          action: 'refund_mark_review',
          actor: actor,
          resource: refund,
          after: { state: refund.state, last_error_code: refund.last_error_code }
        )

        success(refund.reload)
      end
    end
  end
end
