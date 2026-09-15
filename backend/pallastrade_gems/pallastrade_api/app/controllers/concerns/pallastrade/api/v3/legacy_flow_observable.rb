# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      # P0-7 / PRD-20260914-checkout-cart-store-credits-canonical FR-007 →
      # PRD-20260915-checkout-…-b5-…：**legacy 端点三件套**（§45/§46）。
      #
      # 收敛策略（research §9.3 P2）是「流量阈值驱动」：先把打在 legacy 路由上的真实调用
      # 变成**可计数 + 字段齐备**的结构化日志，同时给出**机器可读的弃用信号**；等流量降到
      # 退役阈值（连续 30 天为 0）后再独立立项删除。**本 concern 不改变任何业务行为。**
      #
      # 统一字段契约（六类 legacy 路由一致）：
      #   message             —— 日志 key（默认 `cart.legacy_flow.used`；历史 key/标记经 `message:` 覆盖）
      #   flow_type           —— 哪个 legacy 端点（legacy_cart_gift_cards / …）
      #   entry_point         —— 调用来源（unknown / legacy_one_page / express_checkout）
      #   requested_cart_id   —— 收到的原始 id（含 `or_` / `cart_` 前缀，便于区分调用方）
      #   legacy_identity     —— canonical_cart(`cart_`) / order_table_cart(其余) / unknown
      #   action              —— 控制器动作名
      #   deprecated          —— 恒为 true（该路由已标记弃用）
      #   canonical_successor —— 建议迁移的 canonical 端点
      #
      # 历史 key（**保留、不改语义**，日志管道可能已在消费）：
      #   * `payment.legacy_flow.used` —— `carts/payment_sessions`（P0-7 FR-070/FR-071）
      #   * `[legacy-discount-codes]` / `[legacy-gift-cards]` 标记 —— 经 `message:` 覆盖保留
      #
      # 弃用信号只打在 **legacy 身份**（非 `cart_`）请求上：
      #   `Deprecation: true` / `Warning: 299 - "…"` / `Link: <canonical>; rel="successor-version"`
      # `cart_` canonical 流量（B1–B4 接线的新流程）不受影响——两者共用同一路由形状。
      module LegacyFlowObservable
        extend ActiveSupport::Concern

        # 默认日志 key（`cart_` 域）；历史 key 由调用方经 `message:` 覆盖。
        LEGACY_FLOW_MESSAGE = 'cart.legacy_flow.used'
        # 保守默认 successor（未声明时指向订单域入口）。
        DEFAULT_CANONICAL_SUCCESSOR = '/api/v3/store/orders'

        private

        # 统一结构化日志（字段见文件头）。`message:` 覆盖保留历史 key / 既有标记。
        def log_legacy_flow_usage(flow_type:, entry_point: 'unknown', message: LEGACY_FLOW_MESSAGE, canonical: nil, **extra)
          Rails.logger.info(
            {
              message: message,
              flow_type: flow_type,
              entry_point: entry_point,
              requested_cart_id: params[:cart_id],
              legacy_identity: legacy_identity,
              action: action_name,
              deprecated: true,
              canonical_successor: canonical || legacy_canonical_successor,
              user_agent: (request&.user_agent.presence unless request.nil?)
            }.merge(extra).compact
          )
        end

        # `cart_` 前缀 = canonical 购物车，不是 legacy 流量 → 不计数、不打弃用信号。
        def canonical_cart_request?
          params[:cart_id].to_s.start_with?('cart_')
        end

        def legacy_identity
          return 'canonical_cart' if canonical_cart_request?
          return 'order_table_cart' if params[:cart_id].present?

          'unknown'
        end

        # 每请求一次：日志 + 弃用信号（`cart_` 身份直接返回）。
        def log_legacy_usage_once(flow_type:, canonical: nil, **extra)
          return if canonical_cart_request?
          return if @legacy_flow_logged

          @legacy_flow_logged = true
          log_legacy_flow_usage(flow_type: flow_type, canonical: canonical, **extra)
          mark_legacy_deprecation!(canonical: canonical)
        end

        # 机器可读弃用信号（RFC 8594 `Deprecation` + RFC 7234 `Warning` + RFC 8288 `Link`）。
        # 不设 `Sunset`——删除须独立立项（§46）。
        def mark_legacy_deprecation!(canonical: nil)
          return if canonical_cart_request?
          return unless response

          successor = canonical || legacy_canonical_successor
          response.set_header('Deprecation', 'true')
          response.set_header('Warning', %(299 - "Legacy cart endpoint; migrate to #{successor}"))
          response.set_header('Link', %(<#{successor}>; rel="successor-version"))
        end

        # 各控制器按 §45 matrix 声明 canonical 替代端点（子类可覆盖）。
        def legacy_canonical_successor
          DEFAULT_CANONICAL_SUCCESSOR
        end
      end
    end
  end
end
