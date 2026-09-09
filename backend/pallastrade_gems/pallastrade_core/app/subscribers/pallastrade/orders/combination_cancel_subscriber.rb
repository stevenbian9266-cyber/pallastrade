# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8k (PRD-20260908-payments-rev-p6-8f §11)
#
# Orders::CombinationCancelSubscriber —— payment_combination.cancel_orchestrated
# → Audit + OperationalMetrics 计数。
#
# 事件源：Orders::CombinationCancel 编排成功（canceled > 0）→ combination.publish_event
#   'payment_combination.cancel_orchestrated'（succeeded 组合成员取消编排的聚合事件；组合状态仍
#   succeeded——与状态机 pre-payment cancel 的 payment_combination.canceled 语义不同，勿合并）。
#
# 可靠性：subscriber 默认 async（PallasTrade::Events::SubscriberJob）；Audit.record 内部 rescue 不抛
# （AuditLog 写失败绝不影响主流程）；本订阅者整体 rescue → Rails.logger.error（不阻断事件流/不 re-raise，
# 审计可重放）。
# 健壮性：payload id 支持 prefixed（pcom_）或 raw integer 双模式（镜像 FinancialLedger succeeded 订阅者）；
# combination 缺失 / payload nil → 安全 no-op。
module PallasTrade
  module Orders
    class CombinationCancelSubscriber < PallasTrade::Subscriber
      subscribes_to 'payment_combination.cancel_orchestrated'

      def handle(event)
        payload = event.payload
        combination = find_combination(payload)
        return if combination.nil?

        members = value(payload, 'members') || {}
        canceled_ids = Array(value(payload, 'canceled_order_ids'))

        PallasTrade::Audit.record(
          actor: value(payload, 'canceled_by').presence || 'system',
          action: 'payment_combination_cancel_orchestrated',
          resource: combination,
          after: {
            members: members.as_json,
            canceled_order_ids: canceled_ids
          }
        )

        PallasTrade::OperationalMetrics.count(
          'payment_combination.cancel_orchestrated',
          combination_id: combination.prefixed_id,
          canceled: members['canceled'],
          skipped: members['skipped'],
          failed: members['failed']
        )
      rescue StandardError => e
        Rails.logger.error(
          "[PallasTrade::Orders::CombinationCancelSubscriber] handling failed for combination #{combination&.prefixed_id}: #{e.class} #{e.message}"
        )
      end

      private

      # payload 走 event_payload（string 键）；兼容 symbol 键（直接调用/测试）。
      def value(payload, key)
        payload.try(:[], key) || payload.try(:[], key.to_sym)
      end

      def find_combination(payload)
        id = value(payload, 'id')
        return if id.blank?

        if id.to_s.start_with?('pcom_')
          PallasTrade::PaymentCombination.find_by_param(id)
        else
          PallasTrade::PaymentCombination.find_by(id: id)
        end
      end
    end
  end
end
