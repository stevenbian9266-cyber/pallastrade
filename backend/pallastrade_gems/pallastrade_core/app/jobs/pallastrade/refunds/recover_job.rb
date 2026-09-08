# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-6 (PRD-20260908-payments-rev-p6-6-refund-reverse-recovery)
#
# Refunds::RecoverJob —— 单笔 Refund 恢复（由 RecoverSweeperJob enqueue）。
# 委托 Refunds::Recover（幂等；自身无副作用）。
module PallasTrade
  module Refunds
    class RecoverJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      def perform(refund_id)
        refund = PallasTrade::Refund.find_by(id: refund_id)
        return if refund.nil?

        PallasTrade::Refunds::Recover.call(refund: refund)
      rescue StandardError => e
        # 不 re-raise：避免 sidekiq 自动重试放大副作用（恢复由 sweeper 周期重扫）
        Rails.logger.error("[Refunds::RecoverJob] error refund=#{refund_id}: #{e.class} #{e.message}")
      end
    end
  end
end
