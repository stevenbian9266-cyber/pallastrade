# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-2 (PRD-20260906-payments-rev-p6-2-refund-execution-orchestration)
#
# Refunds::ExecuteJob —— durable Refund 的 async 执行单元（源文档 REV-P6 §12/§16/§57）。
#
# 语义：
#   - provider I/O 只发生在本 Job（不在任何 request/业务事务内，REV-INV-03）。
#   - 幂等（REV-INV-04/05）：Refunds::Execute 内 claim 状态守卫（仅 requested→processing）
#     保证 Job 重试/并发不产生第二笔 PSP 退款；同 Refund 稳定 provider_idempotency_key。
#   - 顶层 rescue 后**不 re-raise**：避免 sidekiq 自动重试触发第二次 provider 调用；
#     异常（如本地投影 DB 错误）后 Refund 停留在 processing/ambiguous durable 态，
#     由 REV-P6-6 Recover/Sweeper 收敛。
#   - ambiguous/failed 结果不自动重退（Execute 已按三态持久化）。
module PallasTrade
  module Refunds
    class ExecuteJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      # @param refund_id [Integer]
      def perform(refund_id)
        refund = PallasTrade::Refund.find_by(id: refund_id)
        return if refund.nil?
        return if refund.state.in?(PallasTrade::Refund::TERMINAL_STATES)

        PallasTrade::Refunds::Execute.call(refund: refund, raise_on_failure: false)
      rescue StandardError => e
        Rails.logger.error(
          "[Refunds::ExecuteJob] unexpected error refund=#{refund&.prefixed_id || refund_id}: #{e.class} #{e.message}"
        )
      end
    end
  end
end
