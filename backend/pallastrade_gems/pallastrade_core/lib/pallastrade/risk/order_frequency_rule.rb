# frozen_string_literal: true

# PALLAS-CUSTOM: 防刷单规则（PRD-20260828 P8）——同用户 N 分钟内完成订单数超限即拒绝。
# 阈值：store.preferred_order_frequency_limit 回退 Config[:order_frequency_limit]（默认 nil=关闭）；
# 窗口：Config[:order_frequency_window_minutes]（默认 10 分钟）。
module PallasTrade
  module Risk
    class OrderFrequencyRule
      def call(order:, user:, store:)
        limit = store&.preferred_order_frequency_limit || PallasTrade::Config[:order_frequency_limit]
        # integer preference 的 nil 会 cast 为 0；0 / nil = 关闭
        return nil if limit.to_i <= 0 || user.blank?

        window_minutes = PallasTrade::Config[:order_frequency_window_minutes] || 10
        since = window_minutes.to_i.minutes.ago
        count = user.orders.for_store(store).where(state: 'complete').where('completed_at > ?', since).count
        return nil if count < limit.to_i

        { code: 'order_frequency_limit', message: "Order frequency limit reached (#{limit} in #{window_minutes} minutes)" }
      end
    end
  end
end
