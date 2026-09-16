# frozen_string_literal: true

module PallasTrade
  module Payments
    module Health
      # PALLAS-CUSTOM: D11 切片1（PRD-20260916-payments-d11-circuit-breaker-health）--
      # 支付健康指标（业务方案 §67.3「健康指标」的只读数据面）。
      #
      # 口径（唯一权威，卡面/熔断判定都调它，禁止各处重算）：
      #   attempts        —— 窗口内该 provider 的 **建会话尝试数**（PaymentSession 行数）
      #   failed          —— 其中 status = 'failed'（provider/链路失败；canceled/expired 不计失败）
      #   failure_rate    —— failed / attempts（attempts = 0 → 0.0）
      #   avg_seconds     —— 终态会话的平均存活时长（`updated_at - created_at` 近似；无终态 → nil）
      #   top_error_codes —— 窗口内入站事件 `action = 'failed'` 的 `last_error_class` Top N
      #
      # ⚠️ 粒度口径（D11 决策 v1）：**provider 级** —— 会话未持久化入口
      #   （`PaymentSessions::Start#option_kind` 仅做建会话前的可用性校验，D8），
      #   因此入口级失败率无真实数据来源。入口级粒度体现在**熔断状态与手工动作**（选项化 provider
      #   逐入口置灰/解除）；自动判定按 provider 级窗口聚合 → 对该 provider 的全部生效入口生效。
      #
      # 说明：只用本地已落库事实，**零 provider 调用**、不加载 payload。
      module Metrics
        DEFAULT_WINDOW = 24.hours
        TERMINAL_STATUSES = %w[completed failed canceled expired].freeze
        TOP_ERROR_CODES = 5

        module_function

        # @param payment_method [PallasTrade::PaymentMethod]
        # @param window [ActiveSupport::Duration]
        # @param now [Time]
        # @return [Hash]
        def call(payment_method:, window: DEFAULT_WINDOW, now: Time.current)
          since = now - window
          sessions = sessions_scope(payment_method, since: since, now: now)
          counts = sessions.group(:status).count
          attempts = counts.values.sum
          failed = counts.fetch('failed', 0)

          {
            window: window.inspect,
            attempts: attempts,
            by_status: counts,
            failed: failed,
            failure_rate: attempts.zero? ? 0.0 : (failed.to_f / attempts).round(4),
            avg_seconds: average_terminal_seconds(sessions),
            top_error_codes: top_error_codes(payment_method, since: since, now: now)
          }
        end

        # 建会话尝试（窗口内）。
        def sessions_scope(payment_method, since:, now:)
          PallasTrade::PaymentSession
            .where(payment_method_id: payment_method.id)
            .where(created_at: since..now)
        end

        # 终态会话平均存活时长（秒，3 位小数；无终态返回 nil）。
        def average_terminal_seconds(sessions)
          terminal = sessions.where(status: TERMINAL_STATUSES)
          count = terminal.count
          return nil if count.zero?

          total = terminal.sum('EXTRACT(EPOCH FROM (updated_at - created_at))')
          (total.to_f / count).round(3)
        end

        # 入站失败事件的错误类 Top N（本地事实；无数据返回 []）。
        # @return [Array<Hash>] [{ 'code' =>, 'count' => }]
        def top_error_codes(payment_method, since:, now:, limit: TOP_ERROR_CODES)
          scope = PallasTrade::PaymentWebhookEvent
                  .where(payment_method_id: payment_method.id, action: 'failed')
                  .where(received_at: since..now)
                  .where.not(last_error_class: nil)

          scope.group(:last_error_class)
               .count
               .sort_by { |code, count| [-count, code.to_s] }
               .first(limit)
               .map { |code, count| { 'code' => code.to_s, 'count' => count } }
        end
      end
    end
  end
end
