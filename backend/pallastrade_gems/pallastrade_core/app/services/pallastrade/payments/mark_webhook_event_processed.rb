# frozen_string_literal: true

module PallasTrade
  module Payments
    # PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance 切片2）——
    # 人工标记已处理（业务方案 §69「动作…标记已处理」）。
    #
    # 用途：运营已线下核实（如 provider 侧已退款 / 已人工对账），不希望该事件继续出现在
    # 待处理队列，且**不重放业务链**。审计口径：`AuditLog(action: 'webhook_mark_processed')`。
    class MarkWebhookEventProcessed
      prepend PallasTrade::ServiceModule::Base

      # @param webhook_event [PallasTrade::PaymentWebhookEvent]
      # @param note [String, nil] 备注（写入审计 after 载荷，可选）
      # @param actor [String, nil]
      # @return [ServiceResult]
      def call(webhook_event:, actor: 'system', note: nil)
        return failure(webhook_event, 'Event cannot be marked processed while processing') if webhook_event.processing?

        webhook_event.mark_processed_manually!

        PallasTrade::Audit.record(
          actor: actor,
          action: 'webhook_mark_processed',
          resource: webhook_event,
          after: {
            provider: webhook_event.provider,
            provider_event_id: webhook_event.provider_event_id,
            event_type: webhook_event.event_type,
            action: webhook_event.action,
            note: note.to_s.strip.presence
          }.compact
        )
        Rails.logger.info(
          message: 'payment.webhook.mark_processed',
          webhook_event_id: webhook_event.id,
          provider: webhook_event.provider,
          provider_event_id: webhook_event.provider_event_id,
          actor: actor
        )

        success(webhook_event)
      end
    end
  end
end
