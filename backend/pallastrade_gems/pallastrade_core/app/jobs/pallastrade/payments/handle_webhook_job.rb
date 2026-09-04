module PallasTrade
  module Payments
    # P0-2 (2026-09-02): Webhook 可靠性外壳 —— 围绕 PaymentWebhookEvent 的
    # processing/processed/failed 生命周期包裹原 HandleWebhook。
    #
    # 语义：
    #   - mark_processing!（attempt_count+1）
    #   - 调原 Payments::HandleWebhook（业务幂等逻辑不变）
    #   - 成功 → mark_processed!
    #   - 未知/transient 异常 → mark_failed! + raise（交 Job retry；PRD FR-024）
    #
    # 兼容旧路径（payment_method_id + action + payment_session_id，无事件记录时）。
    class HandleWebhookJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.payment_webhooks

      retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
      retry_on ActiveRecord::LockWaitTimeout, wait: 5.seconds, attempts: 3
      discard_on ActiveRecord::RecordNotFound

      def perform(payment_method_id: nil, action: nil, payment_session_id: nil, webhook_event_id: nil)
        if webhook_event_id.present?
          perform_with_event(webhook_event_id)
        else
          perform_legacy(payment_method_id, action, payment_session_id)
        end
      end

      private

      def perform_with_event(webhook_event_id)
        event = PallasTrade::PaymentWebhookEvent.find(webhook_event_id)

        # 已在处理中/已成功 → 幂等跳过（防 Job 重复执行）
        return if event.status == 'processing' && event.processing_at.present? &&
          event.processing_at > 1.minute.ago

        event.mark_processing!

        result = PallasTrade::Dependencies.payments_handle_webhook_service.constantize.call(
          payment_method: event.payment_method,
          action: event.action.to_sym,
          payment_session: event.payment_session
        )

        if result.failure?
          # 业务确定性失败（订单取消 / no_payment_found 等）→ 记录 failed，
          # 不 raise（不无限重试）；由 Manual Replay 人工处理。
          event.mark_failed!(PallasTrade::Payments::WebhookProcessingError.new(result.error.to_s))
          return
        end

        event.mark_processed!
      rescue StandardError => e
        # transient / DB 锁类 / 未知异常：记录 failed 后 raise → BaseJob retry_on
        # 自动重试（attempt_count +1）。RecordNotFound 由 discard_on 处理。
        begin
          event.mark_failed!(e) if defined?(event) && event&.persisted?
        rescue StandardError
          nil
        end
        raise e
      end

      def perform_legacy(payment_method_id, action, payment_session_id)
        return if payment_method_id.blank? || payment_session_id.blank?

        payment_method = PallasTrade::PaymentMethod.find(payment_method_id)
        payment_session = PallasTrade::PaymentSession.find(payment_session_id)

        PallasTrade::Dependencies.payments_handle_webhook_service.constantize.call(
          payment_method: payment_method,
          action: action.to_sym,
          payment_session: payment_session
        )
      end
    end
  end
end
