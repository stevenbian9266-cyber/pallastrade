module PallasTrade
  module Api
    module V3
      module Webhooks
        class PaymentsController < ActionController::API
          include ActionController::RateLimiting
          include PallasTrade::Core::ControllerHelpers::Store

          RATE_LIMIT_RESPONSE = lambda {
            [429, { 'Content-Type' => 'application/json', 'Retry-After' => '60' },
             [{ error: { code: 'rate_limit_exceeded', message: 'Too many requests' } }.to_json]]
          }

          rate_limit to: 120, within: 1.minute,
                     store: Rails.cache,
                     by: -> { request.remote_ip },
                     with: RATE_LIMIT_RESPONSE

          # POST /api/v3/webhooks/payments/:payment_method_id
          #
          # Verifies the webhook signature synchronously (returns 401 if invalid),
          # persists the verified event for dedup/retry/replay (P0-2), then
          # enqueues async processing and returns 200 immediately.
          #
          # 30s delay = contention mitigation（让 storefront 自己的 complete 先落地），
          # 不是事件顺序保证（PRD FR-025）。
          def create
            payment_method = current_store.payment_methods.find_by_prefix_id!(params[:payment_method_id])

            # Signature verification must be synchronous — invalid = 401
            result = payment_method.parse_webhook_event(request.raw_post, request.headers)

            # Unsupported event / no local session — acknowledge receipt
            return head :ok if result.nil?

            # P0-2: 落库已验签事件（DB 级去重）。
            webhook_event, duplicate =
              PallasTrade::Payments::WebhookEventStore.record(payment_method, result)

            # 重复投递（相同 provider_event_id 已存在）→ ACK 200，不重复入队；
            # FAILED 状态恢复由 Job Retry / Manual Replay 处理（PRD FR-022）。
            return head :ok if duplicate

            if webhook_event.present?
              # 新事件：入队（30s 延迟），Job 内 mark_processing → HandleWebhook
              PallasTrade::Payments::HandleWebhookJob.set(wait: 30.seconds).perform_later(
                webhook_event_id: webhook_event.id
              )
            else
              # 无法落库（provider 无事件 id）→ 退回旧路径（兼容非 Stripe provider）
              PallasTrade::Payments::HandleWebhookJob.set(wait: 30.seconds).perform_later(
                payment_method_id: payment_method.id,
                action: result[:action].to_s,
                payment_session_id: result[:payment_session].id
              )
            end

            head :ok
          rescue PallasTrade::PaymentMethod::WebhookSignatureError
            head :unauthorized
          rescue ActiveRecord::RecordNotFound
            head :not_found
          rescue StandardError => e
            # P0-2 (PRD FR-024): 不再 swallow。未知/基础设施异常返回 500，
            # 让 provider（Stripe 等）按 Retry-After 重投本事件。
            Rails.error.report(e, source: 'PallasTrade.webhooks.payments')
            head :internal_server_error
          end
        end
      end
    end
  end
end
