# frozen_string_literal: true

# PALLAS-CUSTOM: D11 切片1（PRD-20260916-payments-d11-circuit-breaker-health）--
# 支付路由熔断（业务方案 §67.3）：把「provider 抖动」变成入口级软置灰，而不是让用户踩坑。
#
# 模块职责（唯一权威）：
#   - 时间解析（breaker 状态里的 ISO 字符串 ↔ Time）
#   - 判定与恢复：`CircuitBreaker::Evaluate`（见同目录 evaluate.rb）
#   - 巡检作业：`PallasTrade::Payments::CircuitBreaker::SweepJob`
#
# 铁律：**零资金副作用** —— 只读写 `PaymentMethod#metadata` 与 `AuditLog`；
# 不取消会话、不改支付/订单/库存。资金安全仍由既有链路（PaymentFactResolver / recovery）负责。
module PallasTrade
  module Payments
    module CircuitBreaker
      module_function

      # 宽松解析（Time / ActiveSupport::TimeWithZone / ISO 字符串）；非法返回 nil。
      # @return [Time, nil]
      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        return value.to_time if value.respond_to?(:to_time) && !value.is_a?(String)

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
