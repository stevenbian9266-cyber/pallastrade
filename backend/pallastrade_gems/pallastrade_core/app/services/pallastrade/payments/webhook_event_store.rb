# frozen_string_literal: true

module PallasTrade
  module Payments
    # P0-2 (2026-09-02): Webhook Event Store 服务 —— 把已验签的 provider event
    # 落库为 PaymentWebhookEvent 事实记录，供去重 / 重试 / 重放 / 审计。
    #
    # 这是可靠性外壳：只负责持久化 + 去重判定，不执行业务逻辑。
    # 业务处理仍在 Payments::HandleWebhook（+ Carts::Complete）。
    #
    # 用法（webhook controller）：
    #   event = WebhookEventStore.record(payment_method, parse_result)
    #   event.duplicate?  → ACK 200（不重复入队）
    #   event.new_record?  → enqueue HandleWebhookJob(webhook_event_id:)
    class WebhookEventStore
      # @param payment_method [PallasTrade::PaymentMethod]
      # @param parse_result [Hash] gateway#parse_webhook_event 返回值
      #   { action:, payment_session:, metadata: { <provider>_event: event } }
      # @return [Array(PallasTrade::PaymentWebhookEvent, Boolean)] [event, duplicate]
      #   duplicate=true → 已存在相同 provider_event_id（调用方 ACK 200，不重复入队）
      #   返回 [nil, false] → 无法落库（provider 无事件 id）→ 调用方走旧路径
      def self.record(payment_method, parse_result)
        new(payment_method, parse_result).call
      end

      def initialize(payment_method, parse_result)
        @payment_method = payment_method
        @parse_result = parse_result || {}
        @metadata = @parse_result[:metadata] || {}
      end

      def call
        provider_event = find_provider_event
        attrs = extract_attrs(provider_event)
        return [nil, false] if attrs.nil?

        PaymentWebhookEvent.create_unique(
          provider: provider_name,
          provider_event_id: attrs[:provider_event_id],
          payment_method_id: payment_method.id,
          payment_session_id: parse_result[:payment_session]&.id,
          action: parse_result[:action].to_s,
          event_type: attrs[:event_type],
          provider_created_at: attrs[:provider_created_at],
          payload: attrs[:payload]
        )
      end

      private

      attr_reader :payment_method, :parse_result, :metadata

      def provider_name
        return payment_method.provider_name if payment_method.respond_to?(:provider_name) && payment_method.provider_name.present?

        payment_method.type.to_s.demodulize.underscore.presence || 'unknown'
      end

      # metadata 形如 { stripe_event: <Stripe::Event>, adyen_event: <Event>, ... }
      def find_provider_event
        key = metadata.keys.find { |k| k.to_s.end_with?('_event') }
        key ? metadata[key] : nil
      end

      # 提取 provider-neutral 字段；无法提取（无 provider_event_id）→ nil（跳过落库）。
      def extract_attrs(provider_event)
        return nil if provider_event.nil?

        event_id = safe_read(provider_event, :id)
        return nil if event_id.blank?

        {
          provider_event_id: event_id.to_s,
          event_type: safe_read(provider_event, :type).presence ||
            safe_read(provider_event, :code).presence,
          provider_created_at: safe_read(provider_event, :created).presence,
          payload: build_payload(provider_event)
        }
      end

      def build_payload(provider_event)
        return provider_event.to_json if provider_event.respond_to?(:to_json)

        if provider_event.respond_to?(:payload)
          payload = provider_event.payload
          payload.respond_to?(:to_json) ? payload.to_json : payload
        else
          provider_event.to_s
        end
      end

      def safe_read(object, method)
        object.respond_to?(method) ? object.public_send(method) : nil
      end
    end
  end
end
