# frozen_string_literal: true

module PallasTrade
  module Payments
    # P0-2 (2026-09-02): Manual Webhook Replay（PRD FR-026）。
    #
    # 复用原 PaymentWebhookEvent 记录 → attempt_count+1 → 走同一
    # HandleWebhookJob（即同一 HandleWebhook 业务链）→ 写 Audit。
    #
    # 禁止制造新的假 Provider Event；Replay 只重放本地已验签落库的事件。
    class ReplayWebhookEvent
      prepend PallasTrade::ServiceModule::Base

      # @param webhook_event [PallasTrade::PaymentWebhookEvent]
      # @param actor [String, nil] audit actor（如 admin user / 'system'）
      # @return [ServiceResult]
      def call(webhook_event:, actor: 'system')
        return failure(webhook_event, 'Event cannot be replayed while processing') unless webhook_event.replayable?

        # 重放与首次处理完全一致：直接入队同一 Job（Job 内 mark_processing → +1）。
        PallasTrade::Payments::HandleWebhookJob.perform_later(webhook_event_id: webhook_event.id)

        # P0-6 (PRD FR-064): 敏感操作写 Audit + 结构化 Trace 日志。
        PallasTrade::Audit.record(
          actor: actor,
          action: 'webhook_replay',
          resource: webhook_event,
          after: {
            provider: webhook_event.provider,
            provider_event_id: webhook_event.provider_event_id,
            event_type: webhook_event.event_type,
            action: webhook_event.action,
            attempt_count: webhook_event.attempt_count
          }
        )
        Rails.logger.info(
          message: 'payment.webhook.replay',
          webhook_event_id: webhook_event.id,
          provider: webhook_event.provider,
          provider_event_id: webhook_event.provider_event_id,
          action: webhook_event.action,
          actor: actor
        )

        success(webhook_event)
      end
    end
  end
end
