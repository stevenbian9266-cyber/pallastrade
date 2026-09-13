# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-7 (PRD-20260913-payments-dsp-p7-7-admin-disputes-console)
#
# Disputes::MarkManualReview —— 运营在 Console 主动把争议标记为「需人工复核」（源计划 §67 Mark Manual Review）。
#
# 语义（与 P7-6 收敛的人工通道**同一约定**，避免两套「人工态」口径）：
#   - `attention_reason`：仅当为空时写入 `operator_review`（**永不覆盖**已有原因——P7-1/P7-6 的原因更具体，
#     如 `unlinked_payment` / `provider_conflict` / `journal_gap`）；
#   - `state = manual_review`（若尚未；人工态出入自由，**允许从终态进入**——运营事后复核是合法场景）；
#   - 审计：`PallasTrade::Audit.record(action: 'dispute_mark_review', ...)`（actor 来自 Console 的 `audit_actor`）。
#
# 幂等：已在 `manual_review` 且已有 attention → **零写**返回（`already_marked: true`）。
# 铁律（源计划 §49/§50）：零资金副作用——不退款、不重扣、不建 Payment、不改 order/inventory/journal。
module PallasTrade
  module Disputes
    class MarkManualReview
      prepend PallasTrade::ServiceModule::Base

      OPERATOR_REASON = 'operator_review'

      # @param dispute [PallasTrade::Dispute]
      # @param actor [String, Hash, #id] Console 操作者（`audit_actor`）
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ dispute:, already_marked:, attention_reason: }) / failure
      def call(dispute:, actor: 'admin')
        return failure(nil, 'Dispute not found') if dispute.nil?

        dispute = PallasTrade::Dispute.find_by(id: dispute.id)
        return failure(nil, 'Dispute not found') if dispute.nil?

        already_marked = dispute.manual_review? && dispute.attention_reason.present?
        return success({ dispute: dispute, already_marked: true, attention_reason: dispute.attention_reason }) if already_marked

        dispute.with_lock do
          dispute.reload
          dispute.update!(attention_reason: OPERATOR_REASON) if dispute.attention_reason.blank?
          dispute.transition_to!('manual_review') unless dispute.state == 'manual_review'
        end

        PallasTrade::Audit.record(
          action: 'dispute_mark_review',
          actor: actor,
          resource: dispute,
          after: { state: dispute.state, attention_reason: dispute.attention_reason }
        )

        success({ dispute: dispute.reload, already_marked: false, attention_reason: dispute.attention_reason })
      end
    end
  end
end
