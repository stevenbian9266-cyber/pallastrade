# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片1（PRD-20260916-payments-d14-refund-approval；业务方案 §71.1）——
# `Refunds::Submit` —— **人工退款提交入口（策略门的唯一位置）**。
#
# 为什么不是改 `Refunds::Request`：`Request` 同时被网关（stripe/adyen/paypal）与
# `Orders::Cancel` 编排调用（系统来源，无人值守）。把审批门放进内核会让「取消订单退款」
# 因金额超阈值而挂起 → 因此策略门只加在**人工入口**（本服务 + Admin API/后台）。
#
# 语义：
#   - 幂等键：`request_key` 命中既有退款 → 直接返回（`Refund` 层 partial unique index 兜底）；
#   - 策略：`amount <= policy.auto_approve_limit` → `Request(enqueue: true)` + 审计 `refund_auto_approved`；
#     严格大于 → `Request(enqueue: false)` + 建 `RefundApproval(pending)` + 审计 `refund_approval_requested`；
#   - 策略未启用 → 等价于今天的 `Request(enqueue: true)`，**不建审批行、不加额外审计**（零行为变化）；
#   - 币种不在策略范围（策略指定 currency 且不匹配）→ 策略不适用 → 直接执行。
#
# 铁律：**零资金副作用** —— 本服务不调 provider、不改金额；执行只由 `Refunds::ExecuteJob` 承担。
module PallasTrade
  module Refunds
    class Submit
      prepend PallasTrade::ServiceModule::Base

      # @param payment [PallasTrade::Payment]
      # @param amount [Numeric, String]
      # @param reason [PallasTrade::RefundReason]
      # @param refunder_id [Integer, nil] 发起人（admin user id；也是 SoD 校验基准）
      # @param request_key [String, nil] 请求级幂等键（重复提交 → 复用既有退款）
      # @param store [PallasTrade::Store, nil] 显式店铺（缺省从 payment 推导）
      # @param actor [Object] 审计 actor
      # @param reimbursement / commerce_transaction / target_order / payment_split 透传（ownership）
      # @return [PallasTrade::ServiceModule::Result] success(refund) / failure(refund, message)
      def call(payment:, amount:, reason: nil, refunder_id: nil, request_key: nil, store: nil,
               actor: nil, reimbursement: nil, commerce_transaction: nil,
               target_order: nil, payment_split: nil)
        return failure(nil, 'payment_missing') if payment.nil?
        return failure(nil, 'amount_missing') if amount.nil? || amount.to_s.strip.empty?

        key = request_key.to_s.strip.presence
        existing = find_by_request_key(key)
        return success(existing) if existing

        store ||= store_for(payment)
        policy = PallasTrade::Refunds::Policy.for(store)
        approval_required = policy.requires_approval?(amount: amount, currency: payment.currency)

        outcome = PallasTrade::Refunds::Request.call(
          payment: payment, amount: amount, reason: reason, refunder_id: refunder_id,
          reimbursement: reimbursement, commerce_transaction: commerce_transaction,
          target_order: target_order, payment_split: payment_split,
          request_key: key, enqueue: false
        )
        return failure(outcome.value, outcome.error) unless outcome.success?

        refund = outcome.value
        approval = approval_required ? create_approval(refund, policy, refunder_id, store) : nil
        # 入队统一走「外层事务提交后」（若在事务内）——避免事务回滚导致孤儿 job；
        # 待批退款不在此入队（由 Approve 决定）。
        schedule_execution(refund) unless approval_required
        record_audit(refund, policy, approval_required, approval, actor)

        success(refund)
      rescue ActiveRecord::RecordNotUnique
        # 并发同一 request_key：数据层唯一索引兜底 → 复用既有行（绝不产生第二笔）
        existing = find_by_request_key(key)
        return success(existing) if existing

        raise
      end

      private

      def find_by_request_key(key)
        return nil if key.blank?

        PallasTrade::Refund.find_by(request_key: key)
      end

      def create_approval(refund, policy, refunder_id, store)
        PallasTrade::RefundApproval.create!(
          store_id: store&.id,
          refund_id: refund.id,
          status: 'pending',
          amount: refund.amount,
          currency: refund.currency,
          requester_id: refunder_id,
          policy_snapshot: policy.snapshot,
          metadata: { 'source' => 'refunds_submit' }
        )
      end

      # 资金执行入队：遵守「事务提交后入队」纪律（与 REV-P6-4 编排器一致）。
      def schedule_execution(refund)
        refund_id = refund.id
        if ActiveRecord.respond_to?(:after_all_transactions_commit)
          ActiveRecord.after_all_transactions_commit do
            PallasTrade::Refunds::ExecuteJob.perform_later(refund_id)
          end
        else
          PallasTrade::Refunds::ExecuteJob.perform_later(refund_id)
        end
      end

      def record_audit(refund, policy, approval_required, approval, actor)
        if approval_required
          PallasTrade::Audit.record(
            actor: actor.presence || refunder_actor(refund),
            action: 'refund_approval_requested',
            resource: refund,
            metadata: {
              approval_id: approval&.id,
              amount: refund.amount.to_s,
              currency: refund.currency,
              policy: policy.snapshot
            }
          )
        elsif policy.enabled?
          PallasTrade::Audit.record(
            actor: actor.presence || refunder_actor(refund),
            action: 'refund_auto_approved',
            resource: refund,
            metadata: {
              amount: refund.amount.to_s,
              currency: refund.currency,
              policy: policy.snapshot
            }
          )
        end
      end

      def refunder_actor(refund)
        refund.refunder_id ? { type: PallasTrade.admin_user_class.to_s, id: refund.refunder_id } : 'system'
      end

      def store_for(payment)
        payment.order&.store || payment.payment_combination&.store || payment.payment_method&.store
      end
    end
  end
end
