# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片1（PRD-20260916-payments-d14-refund-approval；业务方案 §71.1）——
# `Refunds::Approvals::Reject` —— 超阈值退款的**第二人拒绝**（必填原因）。
#
# 语义：
#   - 职责分离：`approver_id` 必填且 **≠ requester_id**；
#   - `note` 必填（拒绝必须有可审计的理由）；
#   - 仅 `pending` 可拒：已拒绝 → 幂等返回现状；已批准 → failure `approval_already_approved`；
#   - 拒绝后撤销退款请求（`Refund#cancel_request!`，`requested → canceled`）→ **释放可退额度**
#     （`canceled` 不在 CAPACITY_STATES 内），绝不执行 provider I/O；
#   - 审计 `refund_approval_rejected`。
#
# 铁律：**零资金副作用** —— 没有被执行的退款被安全取消，不产生任何 provider 调用。
module PallasTrade
  module Refunds
    module Approvals
      class Reject
        prepend PallasTrade::ServiceModule::Base

        # @param approval [PallasTrade::RefundApproval]
        # @param approver_id [Integer] 拒绝人（admin user id）
        # @param note [String] 必填：拒绝原因
        # @param actor [Object] 审计 actor
        # @return [PallasTrade::ServiceModule::Result] success(approval) / failure(approval, message)
        def call(approval:, approver_id:, note:, actor: nil)
          return failure(nil, 'approval_not_found') if approval.nil?

          approval = PallasTrade::RefundApproval.find_by(id: approval.id)
          return failure(nil, 'approval_not_found') if approval.nil?
          return failure(approval, 'note_required') if note.to_s.strip.empty?
          return failure(approval, 'approver_required') if approver_id.blank?
          return failure(approval, 'approver_must_differ') if approval.requester?(approver_id)

          return success(approval) if approval.rejected?
          return failure(approval, 'approval_already_approved') if approval.approved?

          approval.update!(
            status: 'rejected',
            approver_id: approver_id,
            decided_at: Time.current,
            note: note.to_s.strip
          )

          canceled = cancel_refund(approval)
          record_audit(approval, actor, canceled)

          success(approval)
        end

        private

        # 仅在退款仍未被 PSP 触碰（`requested`）时撤销 → 释放可退额度。
        def cancel_refund(approval)
          refund = approval.refund
          return false if refund.blank?
          return false unless refund.state == 'requested'

          refund.cancel_request!
          true
        end

        def record_audit(approval, actor, canceled)
          PallasTrade::Audit.record(
            actor: actor.presence || { type: PallasTrade.admin_user_class.to_s, id: approval.approver_id },
            action: 'refund_approval_rejected',
            resource: approval.refund,
            metadata: {
              approval_id: approval.id,
              approver_id: approval.approver_id,
              requester_id: approval.requester_id,
              amount: approval.amount.to_s,
              currency: approval.currency,
              refund_canceled: canceled,
              note: approval.note
            }
          )
        end
      end
    end
  end
end
