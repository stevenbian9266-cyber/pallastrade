# frozen_string_literal: true

module PallasTrade
  module Payments
    # PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance 切片2）——
    # 隔离入站 webhook 事件（业务方案 §69「动作…隔离（忽略未知事件）」）。
    #
    # 语义：事件保留留痕，但**不再参与处理**（`replayable?` = false）；可经 `Unquarantine`
    # 路径（模型 `unquarantine!`）复位为 failed 后人工处置。绝不做业务写操作。
    #
    # 审计与可观测沿用 P0-6 口径：写 `AuditLog(action: 'webhook_quarantine')` + 结构化 trace。
    class QuarantineWebhookEvent
      prepend PallasTrade::ServiceModule::Base

      # @param webhook_event [PallasTrade::PaymentWebhookEvent]
      # @param reason [String] 必填（运营可见的隔离理由）
      # @param actor [String, nil] 审计 actor（后台用户 / 'system'）
      # @return [ServiceResult]
      def call(webhook_event:, reason:, actor: 'system')
        reason = reason.to_s.strip
        return failure(webhook_event, 'Quarantine reason is required') if reason.empty?
        return failure(webhook_event, 'Event cannot be quarantined while processing') if webhook_event.processing?

        webhook_event.mark_quarantined!(reason: reason)

        PallasTrade::Audit.record(
          actor: actor,
          action: 'webhook_quarantine',
          resource: webhook_event,
          after: {
            provider: webhook_event.provider,
            provider_event_id: webhook_event.provider_event_id,
            event_type: webhook_event.event_type,
            action: webhook_event.action,
            reason: webhook_event.quarantine_reason
          }
        )
        Rails.logger.info(
          message: 'payment.webhook.quarantine',
          webhook_event_id: webhook_event.id,
          provider: webhook_event.provider,
          provider_event_id: webhook_event.provider_event_id,
          reason: webhook_event.quarantine_reason,
          actor: actor
        )

        success(webhook_event)
      end
    end
  end
end
