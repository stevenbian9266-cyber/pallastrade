# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      # P0-7 / PRD-20260914-checkout-cart-store-credits-canonical FR-007：
      # **legacy 端点流量观测**。收敛策略（research §9.3 P2）是「流量阈值驱动」：
      # 先把打在 legacy resolver 上的真实调用变成可计数的结构化日志，再决定哪些端点
      # 值得迁 canonical，而不是凭猜测补实现。
      #
      # 统一 key `cart.legacy_flow.used`（按 message 计数），字段：
      #   flow_type   —— 哪个 legacy 端点（legacy_cart_gift_cards / ..._store_credits / ...）
      #   entry_point —— 调用来源（unknown / legacy_one_page / express_checkout）
      #   cart_id     —— 收到的原始 id（含 `or_` / `cart_` 前缀，便于区分调用方）
      #
      # 注意：`payment_sessions` 控制器有历史 key `payment.legacy_flow.used`
      # （P0-7 FR-070/FR-071 已上线，日志管道可能已在消费）→ 不迁移、不改语义。
      module LegacyFlowObservable
        extend ActiveSupport::Concern

        private

        def log_legacy_flow_usage(flow_type:, entry_point: 'unknown', message: 'cart.legacy_flow.used', **extra)
          Rails.logger.info(
            {
              message: message,
              flow_type: flow_type,
              entry_point: entry_point,
              requested_cart_id: params[:cart_id],
              user_agent: (request&.user_agent.presence unless request.nil?)
            }.merge(extra).compact
          )
        end

        # `cart_` 前缀 = canonical 购物车，不是 legacy 流量 → 不计数。
        def canonical_cart_request?
          params[:cart_id].to_s.start_with?('cart_')
        end

        def log_legacy_usage_once(flow_type:, **extra)
          return if canonical_cart_request?
          return if @legacy_flow_logged

          @legacy_flow_logged = true
          log_legacy_flow_usage(flow_type: flow_type, **extra)
        end
      end
    end
  end
end
