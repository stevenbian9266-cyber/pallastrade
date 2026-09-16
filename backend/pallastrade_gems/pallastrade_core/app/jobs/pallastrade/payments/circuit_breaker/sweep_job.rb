# frozen_string_literal: true

module PallasTrade
  module Payments
    module CircuitBreaker
      # PALLAS-CUSTOM: D11 切片1（PRD-20260916-payments-d11-circuit-breaker-health）--
      # 熔断巡检（小时级）：对全部 active provider 执行判定与到期恢复（§67.3）。
      #
      # 只读聚合 + metadata 写；**零资金副作用**、零 provider 调用。
      class SweepJob < PallasTrade::BaseJob
        queue_as PallasTrade.queues.default

        retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
        retry_on ActiveRecord::LockWaitTimeout, wait: 5.seconds, attempts: 3

        # @param now [Time, String, nil] 判定基准时刻；nil = 当前时间。
        #   ⚠️ 传入 String 时精度只到秒（`Time.zone.parse`），可能漏掉同秒内新建的会话样本；
        #   调用方/测试应传 Time。
        def perform(now: nil)
          reference = resolve_reference(now)
          opened = []
          restored = []

          PallasTrade::PaymentMethod.where(active: true).find_each do |payment_method|
            result = Evaluate.call(payment_method: payment_method, now: reference)
            next unless result.success?

            opened.concat(result.value[:opened].map { |kind| "#{payment_method.id}:#{kind}" })
            restored.concat(result.value[:restored].map { |kind| "#{payment_method.id}:#{kind}" })
          rescue StandardError => e
            # 单个 provider 判定失败不影响整体巡检（下次巡检重试）
            Rails.logger.warn(
              message: 'payment.circuit_breaker.sweep_failed',
              payment_method_id: payment_method.id,
              error: e.class.name,
              detail: e.message.to_s.truncate(200)
            )
          end

          Rails.logger.info(
            message: 'payment.circuit_breaker.swept',
            opened: opened.count,
            restored: restored.count
          )
          { opened: opened, restored: restored }
        end

        private

        def resolve_reference(now)
          return Time.current if now.blank?
          return now if now.is_a?(Time)

          Time.zone.parse(now.to_s)
        end
      end
    end
  end
end
