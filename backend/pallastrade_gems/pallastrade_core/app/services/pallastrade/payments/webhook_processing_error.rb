# frozen_string_literal: true

module PallasTrade
  module Payments
    # P0-2 (2026-09-02): Webhook 业务确定性失败信号 —— 由 Job 层用于把
    # HandleWebhook 的 failure 结果（非异常路径）记录到事件 last_error，
    # 同时区分于 transient 异常（后者直接 raise，由 Job framework retry）。
    class WebhookProcessingError < StandardError; end
  end
end
