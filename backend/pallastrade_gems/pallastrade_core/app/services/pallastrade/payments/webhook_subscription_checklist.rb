# frozen_string_literal: true

module PallasTrade
  module Payments
    # PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance 切片2）——
    # 订阅核对清单（业务方案 §69「订阅清单：每个 provider 需要订阅哪些事件 + 核对清单（防漏订）」）。
    #
    # 口径（单一权威，页面只渲染不重算）：
    #   expected  —— provider 声明（`PaymentMethod#webhook_expected_actions`，本地 action 维度）
    #   observed  —— 窗口内实际落库的 action 集合（`PaymentWebhookEvent`，按 provider）
    #   missing   —— expected − observed → **漏订候选**（provider 后台未勾选该事件 / 未配置终点）
    #   unknown   —— observed − expected → **未声明事件**（provider 新增类型；建议先隔离再评估订阅）
    #
    # 只读：不发起任何 provider 调用；窗口默认 30 天。
    module WebhookSubscriptionChecklist
      DEFAULT_WINDOW = 30.days

      module_function

      # @param window [ActiveSupport::Duration]
      # @param now [Time]
      # @return [Array<Hash>] 每个 provider 一份清单（按 provider 名排序）
      def call(window: DEFAULT_WINDOW, now: Time.current)
        since = now - window
        payment_methods = PallasTrade::PaymentMethod.all.to_a
        providers = (payment_methods.map { |pm| provider_key(pm) } + observed_providers(since)).compact.uniq.sort

        providers.map { |provider| for_provider(provider, payment_methods: payment_methods, since: since) }
      end

      # @return [Hash]
      def for_provider(provider, payment_methods: nil, since: (Time.current - DEFAULT_WINDOW))
        payment_method = (payment_methods || PallasTrade::PaymentMethod.all.to_a).find do |pm|
          provider_key(pm) == provider
        end

        expected = payment_method ? Array(payment_method.webhook_expected_actions).map(&:to_s).uniq : []
        observed = PallasTrade::PaymentWebhookEvent
                   .where(provider: provider)
                   .where(received_at: since..)
                   .where.not(action: nil)
                   .distinct
                   .pluck(:action)
                   .map(&:to_s)
                   .uniq
                   .sort

        {
          provider: provider,
          configured: payment_method.present?,
          expected: expected.sort,
          expected_events: payment_method ? Array(payment_method.webhook_event_subscriptions).map(&:to_s) : [],
          observed: observed,
          missing: (expected - observed).sort,
          unknown: (observed - expected).sort
        }
      end

      # provider 标识（与 `PaymentWebhookEvent#provider` 同口径：`Gateway.api_type`）。
      def provider_key(payment_method)
        klass = payment_method.class
        klass.respond_to?(:api_type) ? klass.api_type : klass.name
      end

      # 窗口内有事件但已无对应 provider 配置的（历史 provider）也要出现在清单里。
      def observed_providers(since)
        PallasTrade::PaymentWebhookEvent.where(received_at: since..).distinct.pluck(:provider)
      end
    end
  end
end
