# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片1（PRD-20260916-payments-d14-refund-approval；业务方案 §71.1）——
# `Refunds::Approvals::Approve` —— 超阈值退款的**第二人批准**。
#
# 语义：
#   - 职责分离：`approver_id` 必填且 **≠ requester_id**（同人自批 → failure `approver_must_differ`）；
#   - 仅 `pending` 可批：已批准 → 幂等返回现状；已拒绝 → failure `approval_already_rejected`；
#   - 批准成功后把退款交给既有异步执行链（`Refunds::ExecuteJob`，同 `provider_idempotency_key` 幂等）；
#     退款已不在 `requested`（被撤销/已执行）→ 不改状态、不禁用审批行，只记录 `enqueued: false`；
#   - 审计 `refund_approval_approved`（含批准人/阈值快照）。
#
# 铁律：**零资金副作用** —— 本服务不调 provider；执行只由 ExecuteJob 承担。
module PallasTrade
  module Refunds
    module Approvals
      class Approve
        prepend PallasTrade::ServiceModule::Base

        # @param approval [PallasTrade::RefundApproval]
        # @param approver_id [Integer] 批准人（admin user id）
        # @param note [String, nil]
        # @param actor [Object] 审计 actor
        # @return [PallasTrade::ServiceModule::Result] success(approval) / failure(approval, message)
        def call(approval:, approver_id:, note: nil, actor: nil)
          return failure(nil, 'approval_not_found') if approval.nil?

          approval = PallasTrade::RefundApproval.find_by(id: approval.id)
          return failure(nil, 'approval_not_found') if approval.nil?
          return failure(approval, 'approver_required') if approver_id.blank?
          return failure(approval, 'approver_must_differ') if approval.requester?(approver_id)

          return success(approval) if approval.approved?
          return failure(approval, 'approval_already_rejected') if approval.rejected?

          approval.update!(
            status: 'approved',
            approver_id: approver_id,
            decided_at: Time.current,
            note: note.to_s.strip.presence
          )

          enqueued = enqueue_execution(approval)
          record_audit(approval, actor, enqueued)

          success(approval)
        end

        private

        def enqueue_execution(approval)
          refund = approval.refund
          return false if refund.blank?
          return false unless refund.state == 'requested'

          PallasTrade::Refunds::ExecuteJob.perform_later(refund.id)
          true
        end

        def record_audit(approval, actor, enqueued)
          PallasTrade::Audit.record(
            actor: actor.presence || { type: PallasTrade.admin_user_class.to_s, id: approval.approver_id },
            action: 'refund_approval_approved',
            resource: approval.refund,
            metadata: {
              approval_id: approval.id,
              approver_id: approval.approver_id,
              requester_id: approval.requester_id,
              amount: approval.amount.to_s,
              currency: approval.currency,
              enqueued: enqueued,
              policy: approval.policy_snapshot
            }
          )
        end
      end
    end
  end
end
