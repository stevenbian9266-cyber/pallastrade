# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8i (PRD-20260908-payments-rev-p6-8i-recover-auto-scheduling)
#
# ReverseCommerce::RecoverJob —— 单 Order 的跨域收敛（由 RecoverSweeperJob enqueue）。
# 委托 ReverseCommerce::Recover（幂等：restock 自愈 partial-unique + RestockFact；refund 复用
# Refunds::Recover，fresh no-op）。rescue 不 re-raise（避免 sidekiq 自动重试放大副作用——
# 恢复由 sweeper 周期重扫，同 Refunds::RecoverJob 哲学）。
module PallasTrade
  module ReverseCommerce
    class RecoverJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      # @param order_id [Integer]
      def perform(order_id)
        order = PallasTrade::Order.find_by(id: order_id)
        return if order.nil?

        PallasTrade::ReverseCommerce::Recover.call(order: order)
      rescue StandardError => e
        Rails.logger.error("[ReverseCommerce::RecoverJob] error order=#{order_id}: #{e.class} #{e.message}")
      end
    end
  end
end
