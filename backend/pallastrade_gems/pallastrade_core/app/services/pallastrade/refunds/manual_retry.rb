# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8b (PRD-20260908-payments-rev-p6-8b-refund-manual-review-retry)
#
# Refunds::ManualRetry —— 人工触发的确定性重试（危险资金操作，源 REV-P6 §47/§49/§63）。
#   - 仅 failed / ambiguous / manual_review 且持有 provider_idempotency_key 可重试；
#     retry_execution!（→ processing）+ attempt_count+1，随后 enqueue Refunds::ExecuteJob。
#   - 资金执行只经 ExecuteJob → Execute：Execute 对 processing 以同一 provider_idempotency_key 重跑
#     → provider 幂等去重返回真实结果（succeeded→ApplySuccess+Journal / failed / ambiguous），
#     REV-INV-04：单 refund 单键，永不产生第二笔退款。
#   - AP-010：本服务绝不在事务内同步调用 Refunds::Execute；只入队。
#   - 不可用态（requested/processing/succeeded/canceled）或 key 缺失 → failure，零副作用。
#   - 幂等/并发：with_lock + reload + 状态守卫；双点第二次 processing 非 eligible → failure。
module PallasTrade
  module Refunds
    class ManualRetry
      prepend PallasTrade::ServiceModule::Base

      ELIGIBLE_STATES = %w[failed ambiguous manual_review].freeze

      # @param refund [PallasTrade::Refund]
      # @param actor [String, Hash, #id] 审计操作者（PallasTrade::Audit 支持 String/AR/Hash）
      # @return [PallasTrade::ServiceModule::Result] success(value=refund) / failure
      def call(refund:, actor: 'admin')
        return failure(nil, 'Refund not found') if refund.nil?

        refund = PallasTrade::Refund.find_by(id: refund.id)
        return failure(nil, 'Refund not found') if refund.nil?

        refund.with_lock do
          refund.reload
          unless refund.state.in?(ELIGIBLE_STATES)
            return failure(refund, "Refund #{refund.prefixed_id} is not eligible for manual retry (state=#{refund.state})")
          end
          if refund.provider_idempotency_key.blank?
            return failure(refund, 'Provider idempotency key missing — deterministic retry not possible')
          end

          refund.retry_execution!
          refund.attempt_count = refund.attempt_count.to_i + 1
          refund.save!
        end

        PallasTrade::Audit.record(
          action: 'refund_manual_retry',
          actor: actor,
          resource: refund,
          after: { state: refund.state, attempt_count: refund.attempt_count,
                   provider_idempotency_key: refund.provider_idempotency_key }
        )

        # 资金执行只经 async ExecuteJob（同键确定性解决；AP-010 不同步 Execute）
        PallasTrade::Refunds::ExecuteJob.perform_later(refund.id)
        success(refund.reload)
      end
    end
  end
end
