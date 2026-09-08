# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-6 (PRD-20260908-payments-rev-p6-6-refund-reverse-recovery)
#
# Refunds::Recover —— 单笔 Refund 的确定性恢复（源 REV-P6 §45/§46，REV-P6-1 状态机预留
# retry_execution 底座）。**保守自动**（镜像 Transactions::RecoverSweeperJob 哲学）：
#   - requested（从未执行，stale > requested_hours）→ enqueue Refunds::ExecuteJob
#     （幂等 claim + 稳定 provider_idempotency_key；资金执行只经 ExecuteJob → Execute，AP-010），
#     attempt_count 封顶 MAX_AUTO_RETRY_ATTEMPTS，超出 → 停自动，交人工。
#   - processing（provider 已调用但长期无终态，stale > processing_hours）→ mark_ambiguous!
#     （超时收敛；无 provider I/O；REV-INV-04：ambiguous 不自动重退——重试/人工裁决在 REV-P6-8，
#     同 idempotency key 确定性解决）。
#   - ambiguous / failed / manual_review / succeeded / canceled / fresh requested → 不动。
# 幂等：处理分支内 with_lock + 状态守卫；Recover 可安全重复执行。
module PallasTrade
  module Refunds
    class Recover
      prepend PallasTrade::ServiceModule::Base

      MAX_AUTO_RETRY_ATTEMPTS = 5

      # @param refund [PallasTrade::Refund]
      # @param requested_hours [Numeric] requested 未执行判定阈值（默认 1h）
      # @param processing_hours [Numeric] processing 超时判定阈值（默认 6h，provider I/O 秒级）
      # @return [PallasTrade::ServiceModule::Result] success(value=refund) / failure
      def call(refund:, requested_hours: 1, processing_hours: 6)
        return failure(nil, 'Refund not found') if refund.nil?

        refund = PallasTrade::Refund.find_by(id: refund.id)
        return failure(nil, 'Refund not found') if refund.nil?

        if stale_requested_rerun?(refund, requested_hours)
          PallasTrade::Refunds::ExecuteJob.perform_later(refund.id)
        elsif stale_processing_timeout?(refund, processing_hours)
          converge_processing_timeout(refund)
        end
        success(refund.reload)
      end

      private

      def stale_requested_rerun?(refund, requested_hours)
        refund.with_lock do
          refund.reload
          refund.requested? &&
            stale?(refund, requested_hours.hours) &&
            refund.attempt_count.to_i < MAX_AUTO_RETRY_ATTEMPTS
        end
      end

      def stale_processing_timeout?(refund, processing_hours)
        refund.with_lock do
          refund.reload
          refund.processing? && stale?(refund, processing_hours.hours)
        end
      end

      def converge_processing_timeout(refund)
        refund.with_lock do
          refund.reload
          # 超时收敛为 ambiguous（不自动重退，REV-INV-04）
          refund.record_ambiguous!(code: 'RECOVERY_TIMEOUT', message: 'Processing timed out; awaiting deterministic resolution') if refund.processing?
        end
      end

      def stale?(refund, threshold)
        refund.updated_at.nil? || refund.updated_at < Time.current - threshold
      end
    end
  end
end
