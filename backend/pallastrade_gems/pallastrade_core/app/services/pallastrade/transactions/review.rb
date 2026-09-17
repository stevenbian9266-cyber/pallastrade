# frozen_string_literal: true

# PALLAS-CUSTOM: D2（PRD-20260917-payments-d2-manual-review-审核动作-通过并捕获-拒绝并释放；
# 业务方案 §78-D2 / §60.2-3）
#
# Transactions::Review —— `manual_review` 的**人工裁决**唯一入口（排障台「通过并捕获 / 拒绝并释放」）。
#
# 语义（写死，不猜）：
#   * 只接受 `state == 'manual_review'` 的交易；其它状态一律拒绝——自动恢复闭环
#     （Recover / RecoverSweeperJob）与本服务互不越权。
#   * decision = `capture`（通过并捕获）：要求存在**已授权未捕获**（`pending`）的 Payment →
#     `Payment#capture!`（provider 真实捕获）→ `approve_after_review!`（manual_review → finalizing）
#     → **既有** `Transactions::Finalize`（参与者订单完成 + 库存 commit）→ 交易 `completed`。
#     捕获失败 → 交易保持 `manual_review`（可重试，绝不留半状态）；
#     finalize 失败 → 由既有引擎语义落到 `recovery_required` + last_error（资金不回滚，交恢复闭环）。
#   * decision = `release`（拒绝并释放）：**不捕获** → void 未捕获授权（若有）→ 逐参与者订单
#     `Orders::Cancel`（既有原语：库存释放 + 取消台账）→ `release_after_review!` → 交易 `canceled`。
#     **零退款**（`refund_payments: false`；若确有已捕获资金，必须先走 Refunds::Request），
#     历史 Payment / Refund / 账本行零改写。
#   * `reason` **必填**；成功与失败都写审计（`transaction_review_{captured,released,failed}`），
#     记录前后状态、决策、原因、操作人、provider reference。
#   * 幂等键 = `(transaction, decision)` 的审计成功行：重复调用返回 `already_applied`，零副作用。
#   * **人工专用**：本服务只允许由后台控制器调用；任何 job / sweeper / 订阅者调用都是违规
#     （spec 断言调用点唯一）。
#
# 铁律（§30）：不新建交易、不新建 PaymentSession、不调用 `PaymentSessions::Start`；
# 所有资金/库存动作一律委托既有服务与模型方法，不复制第二套逻辑。
module PallasTrade
  module Transactions
    class Review
      prepend PallasTrade::ServiceModule::Base

      DECISIONS = %w[capture release].freeze
      REVIEWABLE_STATES = %w[manual_review].freeze

      # OrderCancellation#reason 是**枚举**（REASONS）；操作人自由文本原因写 note + 审计，
      # 不污染枚举语义（人工裁决归为 staff）。
      RELEASE_CANCEL_REASON = 'staff'.freeze

      AUDIT_CAPTURED = 'transaction_review_captured'
      AUDIT_RELEASED = 'transaction_review_released'
      AUDIT_FAILED = 'transaction_review_failed'

      # 释放链路中任一步不可用 → 整条释放回滚（不留半状态、不静默）
      class ReleaseStepFailed < StandardError; end

      # @param transaction [PallasTrade::CommerceTransaction]
      # @param decision [String] 'capture' | 'release'
      # @param reason [String] 必填（审计证据）
      # @param actor [PallasTrade::User, String, Hash, nil] 操作人（审计）
      # @param provider_reference [String, nil] PSP 侧参考号（审计辅助）
      # @return Result success({ action:, already_applied:, transaction:, detail: }) |
      #         failure({ code: 'transaction_required' | 'invalid_decision' | 'reason_required' |
      #                   'transaction_not_reviewable' | 'no_pending_authorization' |
      #                   'capture_failed' | 'capture_not_completed' | 'finalize_failed' |
      #                   'paid_payment_present' | 'release_failed', ... })
      def call(transaction:, decision:, reason:, actor: nil, provider_reference: nil)
        return failure(nil, { code: 'transaction_required' }) if transaction.nil?

        decision = decision.to_s.strip
        reason = reason.to_s.strip
        unless DECISIONS.include?(decision)
          return failure(transaction, { code: 'invalid_decision', allowed: DECISIONS })
        end
        return failure(transaction, { code: 'reason_required' }) if reason.blank?

        transaction.reload

        # 幂等优先于状态守卫：重放（含状态已推进后）必须返回 already_applied，零副作用。
        applied = applied_audit(transaction, decision)
        if applied
          return success(transaction: transaction, action: decision.to_sym, already_applied: true,
                         detail: applied.after.to_h.merge('audit_log_id' => applied.id))
        end

        unless REVIEWABLE_STATES.include?(transaction.state)
          return failure(transaction, { code: 'transaction_not_reviewable', state: transaction.state })
        end

        if decision == 'capture'
          capture_after_review(transaction: transaction, reason: reason, actor: actor,
                               provider_reference: provider_reference)
        else
          release_after_review(transaction: transaction, reason: reason, actor: actor,
                               provider_reference: provider_reference)
        end
      end

      private

      # 通过并捕获：provider 捕获 → manual_review 出口（finalizing）→ 既有 Finalize 闭环
      def capture_after_review(transaction:, reason:, actor:, provider_reference:)
        payment = capture_candidate(transaction)
        if payment.nil?
          return failed_review(transaction, 'capture', reason, actor, 'no_pending_authorization',
                               provider_reference: provider_reference)
        end

        before_state = transaction.state
        begin
          payment.capture!
          unless payment.reload.completed?
            return failed_review(transaction, 'capture', reason, actor, 'capture_not_completed',
                                 provider_reference: provider_reference,
                                 extra: { payment_state: payment.state })
          end

          transaction.approve_after_review!
        rescue StandardError => e
          return failed_review(transaction, 'capture', reason, actor, 'capture_failed',
                               provider_reference: provider_reference,
                               extra: { error_class: e.class.name, error_message: e.message.to_s })
        end

        outcome = Finalize.call(transaction: transaction)
        unless outcome.success?
          return failed_review(transaction, 'capture', reason, actor, 'finalize_failed',
                               provider_reference: provider_reference,
                               extra: { state: transaction.reload.state,
                                        last_error_code: transaction.last_error_code })
        end

        record_audit(AUDIT_CAPTURED, transaction, decision: 'capture', reason: reason, actor: actor,
                                      provider_reference: provider_reference,
                                      before: { state: before_state },
                                      after: { state: transaction.state },
                                      metadata: { payment_id: payment.id })
        success(transaction: transaction.reload, payment: payment, action: :capture, already_applied: false,
                detail: { state: transaction.state, payment_state: payment.state })
      end

      # 拒绝并释放：不捕获 → void 授权 → 取消参与者订单（库存释放）→ canceled
      def release_after_review(transaction:, reason:, actor:, provider_reference:)
        if paid_payment(transaction)
          return failed_review(transaction, 'release', reason, actor, 'paid_payment_present',
                               provider_reference: provider_reference)
        end

        before_state = transaction.state
        voided = []
        orders = transaction.orders.to_a
        begin
          ActiveRecord::Base.transaction do
            voided = void_pending_authorizations(transaction)
            orders.each do |order|
              result = PallasTrade::Orders::Cancel.call(
                order: order, canceler: canceler_for(actor), reason: RELEASE_CANCEL_REASON, note: reason,
                refund_payments: false, notify_customer: false
              )
              raise ReleaseStepFailed, "order_cancel_failed:#{order.number}:#{order.errors.full_messages.join('|')}" unless result.success?
            end
            transaction.release_after_review!
          end
        rescue StandardError => e
          return failed_review(transaction, 'release', reason, actor, 'release_failed',
                               provider_reference: provider_reference,
                               extra: { error_class: e.class.name, error_message: e.message.to_s })
        end

        record_audit(AUDIT_RELEASED, transaction, decision: 'release', reason: reason, actor: actor,
                                      provider_reference: provider_reference,
                                      before: { state: before_state },
                                      after: { state: transaction.state },
                                      metadata: { voided_payment_ids: voided,
                                                  canceled_order_numbers: orders.map(&:number) })
        success(transaction: transaction.reload, action: :release, already_applied: false,
                detail: { state: transaction.state, voided_payment_ids: voided,
                          canceled_order_numbers: orders.map(&:number) })
      end

      # 可捕获的支付：已授权未捕获（pending）且尚无捕获事实的交易级支付（取最新一笔）。
      def capture_candidate(transaction)
        session_payments(transaction).select(&:pending?).last
      end

      # 已完成（已捕获）资金事实 —— release 分支的存在性证据
      def paid_payment(transaction)
        session_payments(transaction).find(&:completed?)
      end

      def session_payments(transaction)
        ids = transaction.payment_sessions.pluck(:id)
        return [] if ids.empty?

        PallasTrade::Payment.where(payment_session_id: ids).order(:id).to_a
      end

      # 未捕获授权的撤销；任一笔不可撤销 → 整条释放失败（不静默留下一枚可用授权）
      def void_pending_authorizations(transaction)
        session_payments(transaction).select(&:pending?).map do |payment|
          payment.void_transaction!
          raise ReleaseStepFailed, "void_failed:#{payment.id}" unless payment.reload.void?

          payment.id
        end
      end

      def canceler_for(actor)
        actor.is_a?(ActiveRecord::Base) ? actor : nil
      end

      def applied_audit(transaction, decision)
        action = decision == 'capture' ? AUDIT_CAPTURED : AUDIT_RELEASED
        PallasTrade::AuditLog
          .where(action: action, resource_type: transaction.class.name, resource_id: transaction.id)
          .order(:id).last
      end

      def failed_review(transaction, decision, reason, actor, code, provider_reference: nil, extra: {})
        record_audit(AUDIT_FAILED, transaction, decision: decision, reason: reason, actor: actor,
                                      provider_reference: provider_reference,
                                      before: { state: transaction.reload.state },
                                      after: { state: transaction.reload.state },
                                      metadata: { failed_code: code }.merge(extra))
        failure(transaction.reload, { code: code }.merge(extra))
      end

      def record_audit(audit_action, transaction, decision:, reason:, actor:, before:, after:,
                       provider_reference: nil, metadata: {})
        PallasTrade::Audit.record(
          action: audit_action,
          actor: actor.nil? || actor == '' ? 'system' : actor,
          resource: transaction,
          before: before,
          after: after,
          metadata: { decision: decision, reason: reason, provider_reference: provider_reference }
                    .merge(metadata).compact
        )
      end
    end
  end
end
