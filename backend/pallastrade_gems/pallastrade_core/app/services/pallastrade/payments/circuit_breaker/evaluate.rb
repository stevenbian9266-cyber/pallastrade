# frozen_string_literal: true

module PallasTrade
  module Payments
    module CircuitBreaker
      # PALLAS-CUSTOM: D11 切片1（PRD-20260916-payments-d11-circuit-breaker-health）--
      # 熔断判定与恢复（业务方案 §67.3）。
      #
      # 规则（provider 级窗口聚合 → 对每个生效入口分别落状态）：
      #   1) 已到期且 `manual != true` 的置灰 → **自动恢复**（清除状态 + 审计）
      #   2) 已置灰且未到期 → 不动（幂等，不重开窗口）
      #   3) 窗口内样本（建会话尝试数）≥ `min_samples` 且失败率 ≥ `failure_rate_threshold`
      #      → **自动软置灰** `cooldown_seconds`（写状态 + 审计）
      #   4) 样本不足 / 未达阈值 → 不动（避免小样本误判）
      #
      # 手动置灰（`manual: true`）到期**不自动恢复** —— 必须人工解除（§67.3「手动操作」）。
      # 粒度：判定样本 = provider 级窗口聚合（会话未持久化入口，见 `Health::Metrics` 口径说明）；
      #       状态 = 入口级（已选项化 provider 逐入口；未选项化 = provider 级单入口）。
      class Evaluate
        prepend PallasTrade::ServiceModule::Base

        # @param payment_method [PallasTrade::PaymentMethod]
        # @param now [Time]
        # @param window [ActiveSupport::Duration]
        # @return [ServiceResult] value: { opened: [], restored: [], observed: [] }
        def call(payment_method:, now: Time.current, window: PallasTrade::Payments::Health::Metrics::DEFAULT_WINDOW)
          thresholds = payment_method.breaker_thresholds
          min_samples = thresholds['min_samples'].to_i
          rate_threshold = thresholds['failure_rate_threshold'].to_f
          cooldown = thresholds['cooldown_seconds'].to_i

          opened = []
          restored = []
          observed = []
          metrics = nil

          payment_method.effective_payment_options.each do |option|
            kind = option['kind'].to_s
            state = payment_method.breaker_state(kind)
            until_at = CircuitBreaker.parse_time(state&.[]('until'))

            if state.present? && until_at.present? && until_at <= now && state['manual'] != true
              payment_method.soft_enable!(kind)
              write_audit(payment_method, 'payment_option_breaker_restored', kind, state)
              restored << kind
              next
            end

            # 已置灰且未到期（或手动置灰）→ 保持现状（幂等）
            next if state.present? && (until_at.nil? || until_at > now)

            metrics ||= PallasTrade::Payments::Health::Metrics.call(
              payment_method: payment_method, window: window, now: now
            )
            observed << { kind: kind, attempts: metrics[:attempts], failure_rate: metrics[:failure_rate] }

            next if metrics[:attempts] < min_samples || metrics[:attempts].zero?
            next if metrics[:failure_rate] < rate_threshold

            payment_method.soft_disable!(
              kind: kind,
              until_at: now + cooldown.seconds,
              reason: 'auto',
              manual: false,
              failure_rate: metrics[:failure_rate],
              sample_size: metrics[:attempts]
            )
            write_audit(
              payment_method, 'payment_option_auto_soft_disabled', kind,
              payment_method.breaker_state(kind)
            )
            opened << kind
          end

          success({ opened: opened, restored: restored, observed: observed })
        end

        private

        # 熔断是**运营动作**：审计 actor 用 'system'（自动）或后台用户（手动，见控制器）。
        def write_audit(payment_method, action, kind, state)
          PallasTrade::Audit.record(
            actor: 'system',
            action: action,
            resource: payment_method,
            after: {
              payment_method: payment_method.class.api_type,
              kind: kind,
              breaker: state
            }
          )
          Rails.logger.info(
            message: "payment.circuit_breaker.#{action.delete_prefix('payment_option_')}",
            payment_method_id: payment_method.id,
            kind: kind,
            failure_rate: state&.[]('failure_rate'),
            sample_size: state&.[]('sample_size'),
            until: state&.[]('until')
          )
        end
      end
    end
  end
end
